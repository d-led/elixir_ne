import Config

config :elixir_ne,
       :number_of_neurons,
       (System.get_env("N_NEURONS") || "1000") |> String.to_integer()

config :elixir_ne,
       :neuron_simulate_computation_ms,
       (System.get_env("NEURON_SLEEP_FOR_MS") || "100") |> String.to_integer()

config :elixir_ne,
       :prediction_deadline_ms,
       (System.get_env("PREDICTION_DEADLINE_MS") || "130") |> String.to_integer()

config :elixir_ne,
       :prediction_quiescence_deadline_ms,
       (System.get_env("PREDICTION_QUIESCENCE_DEADLINE_MS") || "200") |> String.to_integer()

config :elixir_ne,
       :demo_reply_timeout_ms,
       (System.get_env("DEMO_REPLY_TIMEOUT_MS") || "15000") |> String.to_integer()

# false = Neuron processes, Elixir votes (default). true = 1 BatchVoter per node, Python votes.
config :elixir_ne,
       :use_pythonx,
       (System.get_env("USE_PYTHONX") || "false") in ["1", "true", "yes"]

# Pythonx: minimal env (no deps). Interpreter initializes on first use when this is set.
config :pythonx, :uv_init,
  pyproject_toml: """
  [project]
  name = "elixir_ne"
  version = "0.1.0"
  requires-python = ">=3.10"
  """

# import_config "#{config_env()}.exs"
