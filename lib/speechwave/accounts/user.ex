defmodule Speechwave.Accounts.User do
  use Ecto.Schema
  import Ecto.Changeset

  schema "users" do
    field :email, :string
    field :authenticated_at, :utc_datetime, virtual: true
    field :api_key, :string
    field :plan, Ecto.Enum, values: [:free, :pro, :org], default: :free
    field :is_admin, :boolean, default: false
    field :confirmed_at, :utc_datetime

    has_many :identities, Speechwave.Accounts.UserIdentity

    timestamps(type: :utc_datetime)
  end

  def email_changeset(user, attrs, opts \\ []) do
    user
    |> cast(attrs, [:email])
    |> validate_email(opts)
    |> maybe_generate_api_key()
  end

  defp validate_email(changeset, opts) do
    changeset =
      changeset
      |> update_change(:email, &String.downcase/1)
      |> validate_required([:email])
      |> validate_format(:email, ~r/^[^@,;\s]+@[^@,;\s]+$/,
        message: "must have the @ sign and no spaces"
      )
      |> validate_length(:email, max: 160)

    if Keyword.get(opts, :validate_unique, true) do
      changeset
      |> unsafe_validate_unique(:email, Speechwave.Repo)
      |> unique_constraint(:email)
      |> validate_email_changed()
    else
      changeset
    end
  end

  defp validate_email_changed(changeset) do
    if get_field(changeset, :email) && get_change(changeset, :email) == nil do
      add_error(changeset, :email, "did not change")
    else
      changeset
    end
  end

  defp maybe_generate_api_key(changeset) do
    if get_field(changeset, :api_key) do
      changeset
    else
      generate_api_key(changeset)
    end
  end

  defp generate_api_key(changeset) do
    put_change(
      changeset,
      :api_key,
      :crypto.strong_rand_bytes(32) |> Base.encode16(case: :lower)
    )
  end

  @doc "Used exclusively for plan changes."
  def plan_changeset(user, attrs) do
    user
    |> cast(attrs, [:plan])
    |> validate_required([:plan])
    |> validate_inclusion(:plan, [:free, :pro, :org])
  end
end
