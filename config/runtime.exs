import Config

# config/runtime.exs is executed for all environments, including
# during releases. It is executed after compilation and before the
# system starts, so it is typically used to load production configuration
# and secrets from environment variables or elsewhere. Do not define
# any compile-time configuration in here, as it won't be applied.
# The block below contains prod specific runtime configuration.

if config_env() == :dev do
  # Reload browser tabs when matching files change.
  config :susumi, SusumiWeb.Endpoint,
    live_reload: [
      web_console_logger: true,
      patterns: [
        # Static assets, except user uploads
        ~r"priv/static/(?!uploads/).*\.(js|css|png|jpeg|jpg|gif|svg)$"E,
        # Gettext translations
        ~r"priv/gettext/.*\.po$"E,
        # Router, Controllers, LiveViews and LiveComponents
        ~r"lib/susumi_web/router\.ex$"E,
        ~r"lib/susumi_web/(controllers|live|components)/.*\.(ex|heex)$"E
      ]
    ]
end

if config_env() == :prod do
  alias Susumi.Runtime.{DataDir, LocalConfig}

  dir = DataDir.ensure!()
  local = LocalConfig.load(dir)

  config :susumi, Susumi.Repo,
    database: DataDir.database_path(dir),
    journal_mode: :wal,
    busy_timeout: 5000,
    pool_size: 5

  config :susumi, SusumiWeb.Endpoint,
    http: [ip: {0, 0, 0, 0}, port: local.port],
    url: [host: "localhost"],
    secret_key_base: LocalConfig.secret_key_base!(dir),
    server: true,
    check_origin: :conn

  config :susumi,
    staff_idle_minutes: local.staff_idle_minutes,
    data_dir: dir,
    open_browser: true,
    auto_migrate: true
end
