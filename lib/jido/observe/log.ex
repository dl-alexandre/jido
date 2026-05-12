defmodule Jido.Observe.Log do
  @moduledoc """
  Centralized log threshold for observability with lazy evaluation support.

  This module provides threshold-based logging for Jido's observability system.
  The log threshold can be configured per-environment to control verbosity:

  - `:debug` in development for verbose output
  - `:info` or `:warning` in production for minimal noise

  ## Lazy Logging

  This module supports lazy logging via zero-arity functions. Messages are only
  evaluated if the log level is enabled, preventing unnecessary computation:

      # Lazy - message only computed if debug is enabled
      Log.log_lazy(:debug, fn ->
        "Processing \#{expensive_calculation()} with \#{length(large_list)} items"
      end)

      # Eager - always evaluated (use for simple static strings)
      Log.log(:info, "Simple message")

  ## Configuration

      # config/config.exs
      config :jido, :observability,
        log_level: :info
      
      # config/dev.exs
      config :jido, :observability,
        log_level: :debug

  ## Usage

      alias Jido.Observe.Log
      
      # Only logs if threshold allows :debug level
      Log.log(:debug, "Processing step", agent_id: agent.id, step: 1)
      
      # Always logs in most configurations
      Log.log(:info, "Agent completed", agent_id: agent.id)

      # Lazy logging - message computed only if enabled
      Log.log_lazy(:debug, fn ->
        "Details: \#{inspect(large_data, limit: 100)}"
      end, agent_id: agent.id)
  """

  require Logger

  alias Jido.Observe.Config, as: ObserveConfig

  @type level :: Logger.level()

  @doc """
  Returns the current observability log threshold.

  Reads from application config `:jido, :observability, :log_level`.
  Defaults to `:info` if not configured.
  """
  @spec threshold() :: level()
  def threshold do
    ObserveConfig.observe_log_level(nil)
  end

  @doc """
  Checks if a given log level is currently enabled.

  Returns `true` if messages at the given level would be logged.

  ## Examples

      Log.level_enabled?(:debug)
      # => true if configured log_level is :debug or lower

      Log.level_enabled?(:error)
      # => true in most configurations
  """
  @spec level_enabled?(level()) :: boolean()
  def level_enabled?(level) when level in [:debug, :info, :warning, :error, :emergency] do
    instance = nil
    threshold = ObserveConfig.observe_log_level(instance)
    Jido.Util.cond_log(threshold, level, "", []) == :ok and
      Logger.compare_levels(threshold, level) in [:lt, :eq]
  end

  @doc """
  Conditionally logs a message based on the observability threshold.

  The message is logged only if the threshold level allows it.
  Uses `Jido.Util.cond_log/4` under the hood.

  ## Parameters

  - `level` - The log level for this message (:debug, :info, :warning, :error)
  - `message` - The message to log (string or iodata)
  - `metadata` - Keyword list of metadata to include

  ## Examples

      # With threshold at :info, this won't log
      Log.log(:debug, "Verbose info", step: 1)
      
      # With threshold at :info, this will log
      Log.log(:info, "Important info", agent_id: "abc")
  """
  @spec log(level(), Logger.message(), keyword()) :: :ok
  def log(level, message, metadata \\ []) do
    instance = Keyword.get(metadata, :jido_instance)
    threshold = ObserveConfig.observe_log_level(instance)
    Jido.Util.cond_log(threshold, level, message, metadata)
  end

  @doc """
  Lazy logging - message is only evaluated if the level is enabled.

  This is the preferred pattern for logging expensive computations or
  large data structures. The zero-arity function is only called if
  the log level would actually emit the message.

  ## Parameters

  - `level` - The log level for this message
  - `message_fun` - Zero-arity function that returns the message string
  - `metadata` - Keyword list of metadata to include

  ## Examples

      # Only calls expensive_operation/0 if debug is enabled
      Log.log_lazy(:debug, fn ->
        result = expensive_operation()
        "Result: \#{result}"
      end)

      # Safe for potentially large data
      Log.log_lazy(:debug, fn ->
        "Data: \#{inspect(large_map, limit: 50)}"
      end, request_id: req.id)

      # With safe_inspect from Jido.Observe
      Log.log_lazy(:debug, fn ->
        Jido.Observe.safe_inspect(data, limit: 200, label: "Response")
      end)
  """
  @spec log_lazy(level(), (-> String.t()), keyword()) :: :ok
  def log_lazy(level, message_fun, metadata \\ []) when is_function(message_fun, 0) do
    if level_enabled?(level) do
      log(level, message_fun.(), metadata)
    else
      :ok
    end
  end
end
