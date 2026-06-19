defmodule Speechwave.Accounts.UserNotifier do
  @moduledoc false
  import Swoosh.Email

  alias Speechwave.Mailer

  defp deliver(recipient, subject, body) do
    email =
      new()
      |> to(recipient)
      |> from({"Speechwave", "noreply@contact.speechwave.live"})
      |> subject(subject)
      |> text_body(body)

    with {:ok, _metadata} <- Mailer.deliver(email) do
      {:ok, email}
    end
  end

  @doc "Deliver a magic link sign-in email."
  def deliver_login_instructions(user, url) do
    deliver(user.email, "Sign in to Speechwave", """

    ==============================

    Hi #{user.email},

    Click the link below to sign in to Speechwave. This link expires in 15 minutes.

    #{url}

    If you did not request this, you can safely ignore this email.

    ==============================
    """)
  end

  @doc "Deliver instructions to update a user email."
  def deliver_update_email_instructions(user, url) do
    deliver(user.email, "Update email instructions", """

    ==============================

    Hi #{user.email},

    You can change your email by visiting the URL below:

    #{url}

    If you didn't request this change, please ignore this.

    ==============================
    """)
  end
end
