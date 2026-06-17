defmodule Speechwave.AccountsTest do
  use Speechwave.DataCase

  alias Speechwave.Accounts

  import Speechwave.AccountsFixtures
  alias Speechwave.Accounts.{User, UserConsent, UserToken}

  describe "get_user_by_email/1" do
    test "does not return the user if the email does not exist" do
      refute Accounts.get_user_by_email("unknown@example.com")
    end

    test "returns the user if the email exists" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user_by_email(user.email)
    end
  end

  describe "get_user!/1" do
    test "raises if id is invalid" do
      assert_raise Ecto.NoResultsError, fn ->
        Accounts.get_user!(-1)
      end
    end

    test "returns the user with the given id" do
      %{id: id} = user = user_fixture()
      assert %User{id: ^id} = Accounts.get_user!(user.id)
    end
  end

  describe "register_user/1" do
    test "requires email to be set" do
      {:error, changeset} = Accounts.register_user(%{})

      assert %{email: ["can't be blank"]} = errors_on(changeset)
    end

    test "validates email when given" do
      {:error, changeset} = Accounts.register_user(%{email: "not valid"})

      assert %{email: ["must have the @ sign and no spaces"]} = errors_on(changeset)
    end

    test "validates maximum values for email for security" do
      too_long = String.duplicate("db", 100)
      {:error, changeset} = Accounts.register_user(%{email: too_long})
      assert "should be at most 160 character(s)" in errors_on(changeset).email
    end

    test "validates email uniqueness" do
      %{email: email} = user_fixture()
      {:error, changeset} = Accounts.register_user(%{email: email})
      assert "has already been taken" in errors_on(changeset).email

      # Now try with the uppercased email too, to check that email case is ignored.
      {:error, changeset} = Accounts.register_user(%{email: String.upcase(email)})
      assert "has already been taken" in errors_on(changeset).email
    end

    test "registers users with email only" do
      email = unique_user_email()
      {:ok, user} = Accounts.register_user(valid_user_attributes(email: email))
      assert user.email == email
      assert is_binary(user.api_key)
    end
  end

  describe "sudo_mode?/2" do
    test "validates the authenticated_at time" do
      now = DateTime.utc_now()

      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.utc_now()})
      assert Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -19, :minute)})
      refute Accounts.sudo_mode?(%User{authenticated_at: DateTime.add(now, -21, :minute)})

      # minute override
      refute Accounts.sudo_mode?(
               %User{authenticated_at: DateTime.add(now, -11, :minute)},
               -10
             )

      # not authenticated
      refute Accounts.sudo_mode?(%User{})
    end
  end

  describe "change_user_email/3" do
    test "returns a user changeset" do
      assert %Ecto.Changeset{} = changeset = Accounts.change_user_email(%User{})
      assert changeset.required == [:email]
    end
  end

  describe "deliver_user_update_email_instructions/3" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(user, "current@example.com", url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "change:current@example.com"
    end
  end

  describe "update_user_email/2" do
    setup do
      user = user_fixture()
      email = unique_user_email()

      token =
        extract_user_token(fn url ->
          Accounts.deliver_user_update_email_instructions(%{user | email: email}, user.email, url)
        end)

      %{user: user, token: token, email: email}
    end

    test "updates the email with a valid token", %{user: user, token: token, email: email} do
      assert {:ok, %{email: ^email}} = Accounts.update_user_email(user, token)
      changed_user = Repo.get!(User, user.id)
      assert changed_user.email != user.email
      assert changed_user.email == email
      refute Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email with invalid token", %{user: user} do
      assert Accounts.update_user_email(user, "oops") ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if user email changed", %{user: user, token: token} do
      assert Accounts.update_user_email(%{user | email: "current@example.com"}, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end

    test "does not update email if token expired", %{user: user, token: token} do
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: ~N[2020-01-01 00:00:00]])

      assert Accounts.update_user_email(user, token) ==
               {:error, :transaction_aborted}

      assert Repo.get!(User, user.id).email == user.email
      assert Repo.get_by(UserToken, user_id: user.id)
    end
  end

  describe "generate_user_session_token/1" do
    setup do
      %{user: user_fixture()}
    end

    test "generates a token", %{user: user} do
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.context == "session"
      assert user_token.authenticated_at != nil

      # Creating the same token for another user should fail
      assert_raise Ecto.ConstraintError, fn ->
        Repo.insert!(%UserToken{
          token: user_token.token,
          user_id: user_fixture().id,
          context: "session"
        })
      end
    end

    test "duplicates the authenticated_at of given user in new token", %{user: user} do
      user = %{user | authenticated_at: DateTime.add(DateTime.utc_now(:second), -3600)}
      token = Accounts.generate_user_session_token(user)
      assert user_token = Repo.get_by(UserToken, token: token)
      assert user_token.authenticated_at == user.authenticated_at
      assert DateTime.compare(user_token.inserted_at, user.authenticated_at) == :gt
    end
  end

  describe "get_user_by_session_token/1" do
    setup do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      %{user: user, token: token}
    end

    test "returns user by token", %{user: user, token: token} do
      assert {session_user, token_inserted_at} = Accounts.get_user_by_session_token(token)
      assert session_user.id == user.id
      assert session_user.authenticated_at != nil
      assert token_inserted_at != nil
    end

    test "does not return user for invalid token" do
      refute Accounts.get_user_by_session_token("oops")
    end

    test "does not return user for expired token", %{token: token} do
      dt = ~N[2020-01-01 00:00:00]
      {1, nil} = Repo.update_all(UserToken, set: [inserted_at: dt, authenticated_at: dt])
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "login_user_by_magic_link/1" do
    test "logs in user with valid token" do
      user = user_fixture()
      {encoded_token, _} = generate_user_magic_link_token(user)
      assert {:ok, {logged_in_user, []}} = Accounts.login_user_by_magic_link(encoded_token)
      assert logged_in_user.id == user.id
    end

    test "token is single use" do
      user = user_fixture()
      {encoded_token, _} = generate_user_magic_link_token(user)
      assert {:ok, _} = Accounts.login_user_by_magic_link(encoded_token)
      assert {:error, :not_found} = Accounts.login_user_by_magic_link(encoded_token)
    end

    test "returns error for invalid token" do
      assert {:error, :not_found} = Accounts.login_user_by_magic_link("invalid")
    end

    test "returns error for malformed base64 token" do
      assert {:error, :not_found} = Accounts.login_user_by_magic_link("not!!valid!!base64")
    end
  end

  describe "delete_user_session_token/1" do
    test "deletes the token" do
      user = user_fixture()
      token = Accounts.generate_user_session_token(user)
      assert Accounts.delete_user_session_token(token) == :ok
      refute Accounts.get_user_by_session_token(token)
    end
  end

  describe "deliver_login_instructions/2" do
    setup do
      %{user: user_fixture()}
    end

    test "sends token through notification", %{user: user} do
      token =
        extract_user_token(fn url ->
          Accounts.deliver_login_instructions(user, url)
        end)

      {:ok, token} = Base.url_decode64(token, padding: false)
      assert user_token = Repo.get_by(UserToken, token: :crypto.hash(:sha256, token))
      assert user_token.user_id == user.id
      assert user_token.sent_to == user.email
      assert user_token.context == "login"
    end
  end

  describe "set_user_plan/2" do
    test "updates the user's plan" do
      user = user_fixture()
      assert user.plan == :free
      assert {:ok, updated} = Accounts.set_user_plan(user, :pro)
      assert updated.plan == :pro
    end

    test "rejects invalid plan" do
      user = user_fixture()
      assert {:error, changeset} = Accounts.set_user_plan(user, :invalid)
      assert "is invalid" in errors_on(changeset).plan
    end
  end

  describe "api_key" do
    test "new users are created with a non-nil api_key" do
      user = user_fixture()
      assert is_binary(user.api_key)
      assert String.length(user.api_key) == 64
    end

    test "get_user_by_api_key/1 returns the user for a valid key" do
      user = user_fixture()
      assert Accounts.get_user_by_api_key(user.api_key).id == user.id
    end

    test "get_user_by_api_key/1 returns nil for an unknown key" do
      assert Accounts.get_user_by_api_key("doesnotexist") == nil
    end

    test "regenerate_api_key/1 returns a new api_key different from the old one" do
      user = user_fixture()
      old_key = user.api_key
      {:ok, updated} = Accounts.regenerate_api_key(user)
      assert updated.api_key != old_key
      assert String.length(updated.api_key) == 64
    end

    test "get_user_by_api_key/1 returns nil after key is regenerated" do
      user = user_fixture()
      old_key = user.api_key
      {:ok, _} = Accounts.regenerate_api_key(user)
      assert Accounts.get_user_by_api_key(old_key) == nil
    end
  end

  describe "user_identities" do
    test "find_or_create_user_from_oauth creates user and identity when neither exists" do
      assert {:ok, user} =
               Accounts.find_or_create_user_from_oauth("google", %{
                 "sub" => "google-uid-123",
                 "email" => "newuser@example.com",
                 "email_verified" => true
               })

      assert user.email == "newuser@example.com"

      assert Speechwave.Repo.get_by(Speechwave.Accounts.UserIdentity,
               provider: "google",
               uid: "google-uid-123"
             )
    end

    test "find_or_create_user_from_oauth links identity to existing user with matching email" do
      existing = user_fixture()

      assert {:ok, user} =
               Accounts.find_or_create_user_from_oauth("google", %{
                 "sub" => "google-uid-456",
                 "email" => existing.email,
                 "email_verified" => true
               })

      assert user.id == existing.id
    end

    test "find_or_create_user_from_oauth returns existing user+identity on repeat login" do
      {:ok, user} =
        Accounts.find_or_create_user_from_oauth("github", %{
          "sub" => "gh-uid-789",
          "email" => "repeat@example.com",
          "email_verified" => true
        })

      assert {:ok, same_user} =
               Accounts.find_or_create_user_from_oauth("github", %{
                 "sub" => "gh-uid-789",
                 "email" => "repeat@example.com",
                 "email_verified" => true
               })

      assert same_user.id == user.id
      assert Speechwave.Repo.aggregate(Speechwave.Accounts.UserIdentity, :count) == 1
    end

    test "find_or_create_user_from_oauth returns error when email is not verified" do
      assert {:error, :email_not_verified} =
               Accounts.find_or_create_user_from_oauth("google", %{
                 "sub" => "uid-unverified",
                 "email" => "unverified@example.com",
                 "email_verified" => false
               })
    end

    test "list_user_identities returns all identities for user" do
      user = user_fixture()

      {:ok, _} =
        Accounts.find_or_create_user_from_oauth("google", %{
          "sub" => "g1",
          "email" => user.email,
          "email_verified" => true
        })

      {:ok, _} =
        Accounts.find_or_create_user_from_oauth("github", %{
          "sub" => "gh1",
          "email" => user.email,
          "email_verified" => true
        })

      identities = Accounts.list_user_identities(user)
      assert length(identities) == 2
      assert Enum.map(identities, & &1.provider) |> Enum.sort() == ["github", "google"]
    end

    test "delete_user_identity removes the identity" do
      user = user_fixture()

      {:ok, _} =
        Accounts.find_or_create_user_from_oauth("google", %{
          "sub" => "g2",
          "email" => user.email,
          "email_verified" => true
        })

      [identity] = Accounts.list_user_identities(user)

      assert {:ok, _} = Accounts.delete_user_identity(identity)
      assert Accounts.list_user_identities(user) == []
    end
  end

  describe "UserConsent.changeset/2" do
    test "is valid when granted with granted_at present" do
      changeset =
        UserConsent.changeset(%UserConsent{}, %{
          consent_type: "marketing_email",
          granted: true,
          granted_at: DateTime.utc_now() |> DateTime.truncate(:second),
          source: "login"
        })

      assert changeset.valid?
    end

    test "is invalid when granted: true without granted_at" do
      changeset =
        UserConsent.changeset(%UserConsent{}, %{
          consent_type: "marketing_email",
          granted: true,
          source: "login"
        })

      refute changeset.valid?
      assert errors_on(changeset)[:granted_at]
    end

    test "is valid when granted: false without granted_at" do
      changeset =
        UserConsent.changeset(%UserConsent{}, %{
          consent_type: "marketing_email",
          granted: false,
          source: "login"
        })

      assert changeset.valid?
    end
  end

  describe "grant_consent/3" do
    test "creates a consent record for a new user" do
      user = user_fixture()
      before = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, consent} = Accounts.grant_consent(user, "marketing_email", source: "login")

      assert consent.granted
      assert consent.consent_type == "marketing_email"
      assert consent.source == "login"
      assert DateTime.compare(consent.granted_at, before) in [:gt, :eq]
      assert is_nil(consent.revoked_at)
    end

    test "defaults source to 'login'" do
      user = user_fixture()

      {:ok, consent} = Accounts.grant_consent(user, "marketing_email")

      assert consent.source == "login"
    end

    test "is a no-op when already consented with the same source" do
      user = user_fixture()
      {:ok, original} = Accounts.grant_consent(user, "marketing_email", source: "login")

      {:ok, same} = Accounts.grant_consent(user, "marketing_email", source: "login")

      assert same.id == original.id
      assert same.granted_at == original.granted_at
    end

    test "updates source when already consented with a different source" do
      user = user_fixture()
      {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")

      {:ok, updated} = Accounts.grant_consent(user, "marketing_email", source: "pricing_pro")

      assert updated.source == "pricing_pro"
      assert updated.granted
    end

    test "re-grants after revocation with granted set and revoked_at cleared" do
      user = user_fixture()
      {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")
      {:ok, _} = Accounts.revoke_consent(user, "marketing_email")

      {:ok, reconsented} = Accounts.grant_consent(user, "marketing_email", source: "login")

      assert reconsented.granted
      assert not is_nil(reconsented.granted_at)
      assert is_nil(reconsented.revoked_at)
    end
  end

  describe "revoke_consent/2" do
    test "sets granted: false, records revoked_at, preserves granted_at" do
      user = user_fixture()
      {:ok, consented} = Accounts.grant_consent(user, "marketing_email", source: "login")
      original_granted_at = consented.granted_at
      before_revoke = DateTime.utc_now() |> DateTime.truncate(:second)

      {:ok, revoked} = Accounts.revoke_consent(user, "marketing_email")

      refute revoked.granted
      assert DateTime.compare(revoked.revoked_at, before_revoke) in [:gt, :eq]
      assert revoked.granted_at == original_granted_at
    end

    test "is a no-op (returns {:ok, nil}) for a user who never consented" do
      user = user_fixture()

      assert {:ok, nil} = Accounts.revoke_consent(user, "marketing_email")
    end

    test "is a no-op when already revoked" do
      user = user_fixture()
      {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")
      {:ok, revoked} = Accounts.revoke_consent(user, "marketing_email")
      original_revoked_at = revoked.revoked_at

      {:ok, same} = Accounts.revoke_consent(user, "marketing_email")

      assert same.revoked_at == original_revoked_at
    end
  end

  describe "consented?/2" do
    test "returns false for a new user" do
      user = user_fixture()

      refute Accounts.consented?(user, "marketing_email")
    end

    test "returns true after consent is granted" do
      user = user_fixture()
      {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")

      assert Accounts.consented?(user, "marketing_email")
    end

    test "returns false after consent is revoked" do
      user = user_fixture()
      {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")
      {:ok, _} = Accounts.revoke_consent(user, "marketing_email")

      refute Accounts.consented?(user, "marketing_email")
    end
  end

  describe "get_consent/2" do
    test "returns nil when no record exists" do
      user = user_fixture()

      assert is_nil(Accounts.get_consent(user, "marketing_email"))
    end

    test "returns the consent record after granting" do
      user = user_fixture()
      {:ok, _} = Accounts.grant_consent(user, "marketing_email", source: "login")

      consent = Accounts.get_consent(user, "marketing_email")

      assert %Speechwave.Accounts.UserConsent{} = consent
      assert consent.consent_type == "marketing_email"
      assert consent.granted
    end
  end
end
