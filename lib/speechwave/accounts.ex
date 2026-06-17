defmodule Speechwave.Accounts do
  @moduledoc """
  The Accounts context.
  """

  import Ecto.Query, warn: false
  alias Speechwave.Repo

  alias Speechwave.Accounts.{User, UserConsent, UserIdentity, UserNotifier, UserToken}

  ## Database getters

  @doc """
  Gets a user by email.

  ## Examples

      iex> get_user_by_email("foo@example.com")
      %User{}

      iex> get_user_by_email("unknown@example.com")
      nil

  """
  def get_user_by_email(email) when is_binary(email) do
    Repo.get_by(User, email: email)
  end

  @doc """
  Gets a user by API key.

  ## Examples

      iex> get_user_by_api_key("valid_key")
      %User{}

      iex> get_user_by_api_key("invalid_key")
      nil

  """
  def get_user_by_api_key(api_key) when is_binary(api_key) do
    Repo.get_by(User, api_key: api_key)
  end

  def get_user_by_api_key(_), do: nil

  @doc """
  Regenerates the API key for the given user.

  Returns `{:ok, updated_user}` on success.
  """
  def regenerate_api_key(%User{} = user) do
    new_key = :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)

    user
    |> Ecto.Changeset.change(api_key: new_key)
    |> Repo.update()
  end

  @doc "Returns the consent record for the given user and type, or nil."
  def get_consent(%User{} = user, consent_type) do
    Repo.get_by(UserConsent, user_id: user.id, consent_type: consent_type)
  end

  @doc "Returns true if the user currently has active consent of the given type."
  def consented?(%User{} = user, consent_type) do
    case get_consent(user, consent_type) do
      %UserConsent{granted: true} -> true
      _ -> false
    end
  end

  @doc """
  Grants consent of the given type for the user.

  Idempotent: calling again with the same source is a no-op. Calling with a
  different source updates the source (e.g. upgrading from "login" to
  "pricing_pro" when the user clicks Notify Me). Re-grants after revocation
  record a fresh `granted_at` timestamp.

  Options:
    - `:source` — where consent was collected; defaults to `"login"`.
  """
  def grant_consent(%User{} = user, consent_type, opts \\ []) do
    source = Keyword.get(opts, :source, "login")
    existing = get_consent(user, consent_type)

    cond do
      is_nil(existing) ->
        %UserConsent{user_id: user.id}
        |> UserConsent.changeset(%{
          consent_type: consent_type,
          granted: true,
          granted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          source: source
        })
        |> Repo.insert()

      not existing.granted ->
        existing
        |> UserConsent.changeset(%{
          granted: true,
          granted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          source: source,
          revoked_at: nil
        })
        |> Repo.update()

      existing.source == source ->
        {:ok, existing}

      true ->
        existing
        |> UserConsent.changeset(%{source: source})
        |> Repo.update()
    end
  end

  @doc """
  Revokes consent of the given type for the user.

  Records `revoked_at` for the audit trail but preserves `granted_at` so the
  original consent timestamp remains. Is a no-op (returns `{:ok, nil}`) if no
  consent record exists.
  """
  def revoke_consent(%User{} = user, consent_type) do
    case get_consent(user, consent_type) do
      nil ->
        {:ok, nil}

      consent ->
        consent
        |> UserConsent.changeset(%{
          granted: false,
          revoked_at: DateTime.utc_now() |> DateTime.truncate(:second)
        })
        |> Repo.update()
    end
  end

  @doc """
  Gets a single user.

  Raises `Ecto.NoResultsError` if the User does not exist.

  ## Examples

      iex> get_user!(123)
      %User{}

      iex> get_user!(456)
      ** (Ecto.NoResultsError)

  """
  def get_user!(id), do: Repo.get!(User, id)

  ## User registration

  @doc """
  Registers a user.

  ## Examples

      iex> register_user(%{field: value})
      {:ok, %User{}}

      iex> register_user(%{field: bad_value})
      {:error, %Ecto.Changeset{}}

  """
  def register_user(attrs) do
    %User{}
    |> User.email_changeset(attrs)
    |> Repo.insert()
  end

  @doc """
  Returns an existing user by email, or registers a new one.
  Used by the magic link flow so that submitting an email always succeeds.
  """
  def register_or_get_user_by_email(email) when is_binary(email) do
    case get_user_by_email(email) do
      nil -> register_user(%{email: email})
      user -> {:ok, user}
    end
  end

  @doc """
  Finds or creates a user from an OAuth provider callback.

  Looks up an existing identity by {provider, uid}. If found, returns the
  associated user. If not found, upserts a user by email and creates the
  identity record. Returns {:error, :email_not_verified} if the provider
  did not verify the email.
  """
  # Microsoft doesn't send email_verified; email comes from the optional "email" claim
  # or falls back to preferred_username (which is the account's email for personal accounts).
  def find_or_create_user_from_oauth("microsoft", %{"sub" => uid} = user_info) do
    email = user_info["email"] || user_info["preferred_username"]

    if is_nil(email) do
      {:error, :email_not_verified}
    else
      Repo.transaction(fn -> oauth_upsert("microsoft", uid, email) end)
    end
  end

  def find_or_create_user_from_oauth(provider, %{"sub" => uid, "email" => email} = user_info) do
    # Reject if explicitly false OR absent — a missing field is not the same as verified.
    if user_info["email_verified"] != true do
      {:error, :email_not_verified}
    else
      Repo.transaction(fn -> oauth_upsert(provider, uid, email) end)
    end
  end

  defp oauth_upsert(provider, uid, email) do
    case Repo.get_by(UserIdentity, provider: provider, uid: uid) do
      %UserIdentity{} = identity ->
        Repo.preload(identity, :user).user

      nil ->
        with {:ok, user} <- register_or_get_user_by_email(email),
             {:ok, _identity} <-
               %UserIdentity{}
               |> UserIdentity.changeset(%{provider: provider, uid: uid, user_id: user.id})
               |> Repo.insert() do
          user
        else
          {:error, reason} -> Repo.rollback(reason)
        end
    end
  end

  @doc "Returns all OAuth identities for the given user."
  def list_user_identities(%User{} = user) do
    Repo.all(from(ui in UserIdentity, where: ui.user_id == ^user.id))
  end

  @doc "Returns the identity for a given provider and uid, or nil."
  def get_identity_by_provider_uid(provider, uid) do
    Repo.get_by(UserIdentity, provider: provider, uid: uid)
  end

  @doc "Deletes an OAuth identity."
  def delete_user_identity(%UserIdentity{} = identity) do
    Repo.delete(identity)
  end

  @doc """
  Links an OAuth identity directly to an existing user.
  Used by the settings connect flow where the logged-in user is already known.
  """
  def link_identity_to_user(%User{} = user, provider, uid) do
    %UserIdentity{}
    |> UserIdentity.changeset(%{provider: provider, uid: uid, user_id: user.id})
    |> Repo.insert()
  end

  ## Settings

  @doc """
  Checks whether the user is in sudo mode.

  The user is in sudo mode when the last authentication was done no further
  than 20 minutes ago. The limit can be given as second argument in minutes.
  """
  def sudo_mode?(user, minutes \\ -20)

  def sudo_mode?(%User{authenticated_at: ts}, minutes) when is_struct(ts, DateTime) do
    DateTime.after?(ts, DateTime.utc_now() |> DateTime.add(minutes, :minute))
  end

  def sudo_mode?(_user, _minutes), do: false

  @doc """
  Returns an `%Ecto.Changeset{}` for changing the user email.

  See `Speechwave.Accounts.User.email_changeset/3` for a list of supported options.

  ## Examples

      iex> change_user_email(user)
      %Ecto.Changeset{data: %User{}}

  """
  def change_user_email(user, attrs \\ %{}, opts \\ []) do
    User.email_changeset(user, attrs, opts)
  end

  @doc """
  Updates the user email using the given token.

  If the token matches, the user email is updated and the token is deleted.
  """
  def update_user_email(user, token) do
    context = "change:#{user.email}"

    Repo.transaction(fn ->
      with {:ok, query} <- UserToken.verify_change_email_token_query(token, context),
           %UserToken{sent_to: email} <- Repo.one(query),
           {:ok, updated_user} <- Repo.update(User.email_changeset(user, %{email: email})),
           {_count, _result} <-
             Repo.delete_all(from(UserToken, where: [user_id: ^user.id, context: ^context])) do
        updated_user
      else
        _ -> Repo.rollback(:transaction_aborted)
      end
    end)
  end

  ## Session

  @doc """
  Generates a session token.
  """
  def generate_user_session_token(user) do
    {token, user_token} = UserToken.build_session_token(user)
    Repo.insert!(user_token)
    token
  end

  @doc """
  Gets the user with the given signed token.

  If the token is valid `{user, token_inserted_at}` is returned, otherwise `nil` is returned.
  """
  def get_user_by_session_token(token) do
    {:ok, query} = UserToken.verify_session_token_query(token)
    Repo.one(query)
  end

  @doc """
  Logs the user in by magic link token. The token is single-use and deleted on success.
  """
  def login_user_by_magic_link(token) do
    case UserToken.verify_magic_link_token_query(token) do
      {:ok, query} ->
        case Repo.one(query) do
          {user, token_record} ->
            Repo.delete!(token_record)
            {:ok, {user, []}}

          nil ->
            {:error, :not_found}
        end

      :error ->
        {:error, :not_found}
    end
  end

  @doc ~S"""
  Delivers the update email instructions to the given user.

  ## Examples

      iex> deliver_user_update_email_instructions(user, current_email, &url(~p"/users/settings/confirm-email/#{&1}"))
      {:ok, %{to: ..., body: ...}}

  """
  def deliver_user_update_email_instructions(%User{} = user, current_email, update_email_url_fun)
      when is_function(update_email_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "change:#{current_email}")

    Repo.insert!(user_token)
    UserNotifier.deliver_update_email_instructions(user, update_email_url_fun.(encoded_token))
  end

  @doc """
  Delivers the magic link login instructions to the given user.
  """
  def deliver_login_instructions(%User{} = user, magic_link_url_fun)
      when is_function(magic_link_url_fun, 1) do
    {encoded_token, user_token} = UserToken.build_email_token(user, "login")
    Repo.insert!(user_token)
    UserNotifier.deliver_login_instructions(user, magic_link_url_fun.(encoded_token))
  end

  @doc """
  Deletes the signed token with the given context.
  """
  def delete_user_session_token(token) do
    Repo.delete_all(from(UserToken, where: [token: ^token, context: "session"]))
    :ok
  end

  @doc "Updates a user's plan. Called by Stripe webhooks or manually via seeds."
  def set_user_plan(%User{} = user, plan) do
    user
    |> User.plan_changeset(%{plan: plan})
    |> Repo.update()
  end
end
