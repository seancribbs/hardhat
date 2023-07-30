import Config

if config_env() == :test do
  config :opentelemetry,
    traces_exporter: :none
end
