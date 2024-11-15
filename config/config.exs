import Config

config :elixir_ne,
       :number_of_neurons,
       (System.get_env("N_NEURONS") || "1000") |> String.to_integer()

config :elixir_ne,
       :neuron_simulate_computation_ms,
       (System.get_env("NEURON_SLEEP_FOR_MS") || "100") |> String.to_integer()

config :elixir_ne,
       :prediction_deadline_ms,
       (System.get_env("PREDICTION_DEADLINE_MS") || "130")  |> String.to_integer()


# import_config "#{config_env()}.exs"
