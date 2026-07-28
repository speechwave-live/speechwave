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
    field :overlay_size_percent, :integer
    field :fireworks_enabled, :boolean, default: true
    field :customize_overlay_size, :boolean, virtual: true, default: true

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

  @doc """
  Updates a user's Chrome-extension overlay settings. `overlay_size_percent`
  may be nil (meaning "use the tuning module's default"); when present it
  must be between the tuning module's minimum and 100.

  `customize_overlay_size` is a virtual toggle (defaulting to `true` so
  callers that don't know about it see unchanged behavior): when explicitly
  set to a falsy value, `overlay_size_percent` is forced back to `nil`
  regardless of what was submitted for it, restoring "inherit the tuning
  default" semantics.
  """
  def extension_settings_changeset(user, attrs) do
    user
    |> cast(attrs, [:overlay_size_percent, :fireworks_enabled, :customize_overlay_size])
    |> maybe_clear_overlay_size_percent()
    |> validate_number(:overlay_size_percent,
      greater_than_or_equal_to: Speechwave.ExtensionTuning.current().min_overlay_size_percent,
      less_than_or_equal_to: 100
    )
  end

  defp maybe_clear_overlay_size_percent(changeset) do
    if Ecto.Changeset.get_field(changeset, :customize_overlay_size) do
      changeset
    else
      Ecto.Changeset.put_change(changeset, :overlay_size_percent, nil)
    end
  end
end
