defmodule CaptainFact.UserPermissions do
  @moduledoc """
  Check and log user permissions. State is a map looking like this :
  ```
  %{
    user_id => %{
      :action_atom => 42 # Number of occurences in the last 24h
    }
  }
  ```
  """

  require Logger
  import Ecto.Query
  alias CaptainFact.{ Repo, User }

  defmodule PermissionsError do
    defexception message: "forbidden"
  end

  @name __MODULE__
  @confirmed_user_threshold 50
  @min_reputations %{
    add_comment: -25,
    add_video: 15,
    add_speaker: 15,
    edit_speaker: 30,
    add_statement: 15,
    vote_up: 15,
    approve_history_action: 30,
    flag_comment: 40,
    approve_history_action: 0,
    flag_history_action: 40,
    vote_down: 80,
    edit_other_statement: 0,
    remove_statement: 0,
    restore_statement: 0,
    remove_speaker: 0,
    restore_speaker: 0
  }
  @max_limit 100 # A raisonnable limit that users should never exceed
  @limitations %{
    # Should be formed as :
    # limitation_key:       {negative_users_limit, new_users_limit, general_limit}
    add_comment:            {3, 10, @max_limit},
    add_video:              {0, 3, 10},
    # Vote
    vote_up:                {0, 10, @max_limit},
    vote_down:              {0, 10, @max_limit},
    # Flag / Approve
    approve_history_action: {0, 10, @max_limit},
    flag_history_action:    {0, 5, @max_limit},
    flag_comment:           {0, 1, @max_limit},
    # Statements
    add_statement:          {0, 10, @max_limit},
    edit_other_statement:   {0, 3, @max_limit},
    remove_statement:       {0, 1, @max_limit},
    restore_statement:      {0, 2, @max_limit},
    # Speakers
    add_speaker:            {0, 10, 50},
    remove_speaker:         {0, 0, @max_limit},
    edit_speaker:           {0, 5, @max_limit},
    restore_speaker:        {0, 2, @max_limit}
  }

  def start_link() do
    # TODO [Optimization] Start a link for each action to uses multiple processes
    # Or for each user ?
    Logger.info("[UserPermissions] User permissions / limitations watcher starting")
    Agent.start_link(fn -> %{} end, name: @name)
  end

  # --- API ---

  @doc """
  Get an atom describing the vote.
  ## Examples
      iex> alias CaptainFact.{ User, UserPermissions }
      iex> UserPermissions.start_link
      iex> user = %User{id: 1, reputation: 42}
      iex> UserPermissions.check(user, :add_comment)
      :ok
      iex> UserPermissions.check(user, :eat_unicorn)
      {:error, "unknow action"}
      iex> UserPermissions.check(%{user | reputation: -42}, :remove_statement)
      {:error, "not enough reputation"}
      iex> for _ <- 0..5, do: UserPermissions.record_action(user, :flag_comment)
      iex> UserPermissions.check(user, :flag_comment)
      {:error, "limit reached"}
  """
  def check(user = %User{}, action) when is_atom(action) do
    Agent.get(@name, fn state ->
      do_ensure_permissions(state, user, action)
    end)
  end
  def check!(user_id, action) when is_integer(user_id) and is_atom(action) do
     check(do_load_user!(user_id), action)
  end

  @doc """
  Doesn't verify user's limitation nor reputation, you need to check that by yourself
  """
  def record_action(user = %User{}, action) when is_atom(action),
  do: Agent.update(@name, &do_record_action(&1, user, action))
  def record_action(user_id, action) when is_integer(user_id),
  do: record_action(%User{id: user_id}, action)

  @doc """
  The safe way to ensure limitations as state is locked during `func` execution.
  Should be used to verify sensitive actions, but not for those where limitation is high / not
  important because of perfomances impact.
  Raises PermissionsError if user doesn't have the permission.
  If user is an integer, it will be loaded from DB
  """
  def lock!(user = %User{}, action, func) do
    case Agent.get_and_update(@name, fn state ->
      case do_ensure_permissions(state, user, action) do
        :ok ->
          try do
            result = func.(user)
            {{:ok, result}, do_record_action(state, user, action)}
          rescue
            e -> {{:exception, e}, state}
          end
        error -> {error, state}
      end
    end) do
      {:error, message} -> raise PermissionsError, message: message
      {:exception, e} -> raise e
      {:ok, result} -> result
    end
  end
  def lock!(user_id, action, func) when is_integer(user_id) and is_atom(action) do
     lock!(do_load_user!(user_id), action, func)
  end

  def user_nb_action_occurences(user = %User{}, action) do
    Agent.get(@name, &(get_in(&1, [user.id, action]) || 0))
  end

  def limitation(%User{reputation: reputation}, action),
  do: Map.get(@limitations, action) |> elem(do_get_limitation_index(reputation))

  def limitations(), do: @limitations

  def min_reputations(), do: @min_reputations

  @doc """
  (!) ⚡ Should **never** be called directly
  This method in only intended to be called by a scheduler to run 1 time a day
  """
  def reset_limitations(), do: Agent.update(@name, &do_reset_limitations(&1))

  # --- Methods ---
  defp do_reset_limitations(_state) do
    Logger.info("[UserPermissions] Reset today's quotas'")
    %{}
  end

  defp do_ensure_permissions(state, user, action) do
    action_min_reputation = Map.get(@min_reputations, action)
    cond do
      action_min_reputation == nil -> {:error, "unknow action"}
      user.reputation < action_min_reputation -> {:error, "not enough reputation"}
      (get_in(state, [user.id, action]) || 0) >= limitation(user, action) -> {:error, "limit reached"}
      true -> :ok
    end
  end

  defp do_record_action(state, user, action) do
    Map.update(state, user.id, %{action => 1}, fn user_actions ->
      Map.update(user_actions, action, 0, &(&1 + 1))
    end)
  end

  defp do_load_user!(user_id) do
    User
    |> where([u], u.id == ^user_id)
    |> select([:id, :reputation])
    |> Repo.one!()
  end

  defp do_get_limitation_index(reputation) when reputation > @confirmed_user_threshold, do: 2
  defp do_get_limitation_index(reputation) when reputation >= 0, do: 1
  defp do_get_limitation_index(_reputation), do: 0
end