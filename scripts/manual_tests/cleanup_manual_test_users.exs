alias Speechwave.{Accounts.User, Repo}
import Ecto.Query

{count, _} = Repo.delete_all(from u in User, where: like(u.email, "manual-test-%@example.com"))
IO.puts("Deleted #{count} manual-test user(s).")
