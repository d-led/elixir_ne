import Config

config :elixir_ne,
       :number_of_neurons,
       (System.get_env("N_NEURONS") || "1000") |> String.to_integer()

# import_config "#{config_env()}.exs"
