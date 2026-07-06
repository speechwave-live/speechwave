defmodule Speechwave.AccountsFixtures do
  @moduledoc """
  Test helpers for creating entities via the `Speechwave.Accounts` context.
  """

  import Ecto.Query

  alias Speechwave.Accounts
  alias Speechwave.Accounts.Scope

  def unique_user_email, do: "user#{System.unique_integer()}@example.com"

  def valid_user_attributes(attrs \\ %{}) do
    Enum.into(attrs, %{email: unique_user_email()})
  end

  def user_fixture(attrs \\ %{}) do
    {:ok, user} =
      attrs
      |> valid_user_attributes()
      |> Accounts.register_user()

    user
  end

  def consented_user_fixture(consent_opts \\ %{}) do
    user = user_fixture()
    source = Map.get(consent_opts, :source, "login")
    {:ok, _} = Speechwave.Accounts.grant_consent(user, "marketing_email", source: source)
    user
  end

  def user_scope_fixture do
    user = user_fixture()
    user_scope_fixture(user)
  end

  def user_scope_fixture(user) do
    Scope.for_user(user)
  end

  def extract_user_token(fun) do
    {:ok, captured_email} = fun.(&"[TOKEN]#{&1}[TOKEN]")
    [_, token | _] = String.split(captured_email.text_body, "[TOKEN]")
    token
  end

  def generate_user_magic_link_token(user) do
    {encoded_token, user_token} = Accounts.UserToken.build_email_token(user, "login")
    Speechwave.Repo.insert!(user_token)
    {encoded_token, user_token.token}
  end

  def offset_user_token(token, amount_to_add, unit) do
    dt = DateTime.add(DateTime.utc_now(:second), amount_to_add, unit)

    Speechwave.Repo.update_all(
      from(ut in Accounts.UserToken, where: ut.token == ^token),
      set: [inserted_at: dt, authenticated_at: dt]
    )
  end

  def override_token_authenticated_at(token, authenticated_at) when is_binary(token) do
    Speechwave.Repo.update_all(
      from(t in Accounts.UserToken, where: t.token == ^token),
      set: [authenticated_at: authenticated_at]
    )
  end

  def oauth_user_fixture(attrs \\ %{}) do
    email = Map.get(attrs, :email, unique_user_email())
    provider = Map.get(attrs, :provider, "google")
    uid = Map.get(attrs, :uid, "uid-#{System.unique_integer()}")

    {:ok, user} =
      Accounts.find_or_create_user_from_oauth(provider, %{
        "sub" => uid,
        "email" => email,
        "email_verified" => true
      })

    user
  end

  def admin_user_fixture(attrs \\ %{}) do
    user = user_fixture(attrs)

    user
    |> Ecto.Changeset.change(is_admin: true)
    |> Speechwave.Repo.update!()
  end
end
