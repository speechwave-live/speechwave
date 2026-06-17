defmodule Speechwave.Accounts.UserConsent do
  @moduledoc """
  Represents a user's consent record for a given consent type (e.g. "marketing_email").

  One row per `(user_id, consent_type)`. The `granted` boolean reflects current state.
  `granted_at` is set when consent is granted and preserved on revocation for the audit
  trail. `revoked_at` is set when consent is revoked and cleared on re-grant.
  """
  use Ecto.Schema
  import Ecto.Changeset

  alias Speechwave.Accounts.User

  schema "user_consents" do
    belongs_to :user, User
    field :consent_type, :string
    field :granted, :boolean, default: false
    field :granted_at, :utc_datetime
    field :source, :string
    field :revoked_at, :utc_datetime

    timestamps(type: :utc_datetime)
  end

  def changeset(consent, attrs) do
    consent
    |> cast(attrs, [:consent_type, :granted, :granted_at, :source, :revoked_at])
    |> validate_required([:consent_type, :granted])
    |> validate_granted_at_when_granted()
    |> unique_constraint([:user_id, :consent_type])
  end

  # Ensures that whenever consent is granted, a timestamp is recorded.
  # This prevents a corrupted record where granted: true but no granted_at.
  defp validate_granted_at_when_granted(changeset) do
    case get_field(changeset, :granted) do
      true ->
        if get_field(changeset, :granted_at) do
          changeset
        else
          add_error(changeset, :granted_at, "is required when consent is granted")
        end

      _ ->
        changeset
    end
  end
end
