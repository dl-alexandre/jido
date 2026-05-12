# Jido Observability Policy

This document defines the standard observability practices across all `jido_*` repositories. The goal is to maintain consistent, secure, and performant logging and telemetry across the entire Jido ecosystem.

## Overview

All `jido_*` repositories should implement this tiny canonical helper API locally while the API settles. This provides a consistent interface across decoupled repos without tight coupling.

## Canonical Helper API

Each repo should implement these functions locally (copy the tiny implementation):

```elixir
defmodule YourApp.Observe do
  @moduledoc """
  Local observability facade implementing the Jido canonical API.
  Copy this pattern into each jido_* repo.
  """

  require Logger
  alias Jido.Observe.Config

  @type level :: :debug | :info | :warning | :error

  @doc """
  Lazy debug logging. Message computed only if level enabled.
  """
  @spec debug((-> String.t()) | String.t(), keyword()) :: :ok
  def debug(message_fun, metadata \\ []) when is_function(message_fun, 0) or is_binary(message_fun) do
    log(:debug, message_fun, metadata)
  end

  @doc """
  Lazy info logging. Message computed only if level enabled.
  """
  @spec info((-> String.t()) | String.t(), keyword()) :: :ok
  def info(message_fun, metadata \\ []) when is_function(message_fun, 0) or is_binary(message_fun) do
    log(:info, message_fun, metadata)
  end

  @doc """
  Lazy warning logging. Message computed only if level enabled.
  """
  @spec warning((-> String.t()) | String.t(), keyword()) :: :ok
  def warning(message_fun, metadata \\ []) when is_function(message_fun, 0) or is_binary(message_fun) do
    log(:warning, message_fun, metadata)
  end

  @doc """
  Lazy error logging. Message computed only if level enabled.
  """
  @spec error((-> String.t()) | String.t(), keyword()) :: :ok
  def error(message_fun, metadata \\ []) when is_function(message_fun, 0) or is_binary(message_fun) do
    log(:error, message_fun, metadata)
  end

  @doc """
  Safe inspect with truncation for large data structures.
  Prevents enormous log lines from crashing systems.

  ## Options

  - `:limit` - Maximum string length before truncation (default: 1000)
  - `:label` - Optional label prefix for the output

  ## Examples

      safe_inspect(large_map, limit: 500)
      # => "#Map<...{truncated at 500 chars}>"

      safe_inspect(data, label: "API response")
      # => "API response: %{key: value}"
  """
  @spec safe_inspect(term(), keyword()) :: String.t()
  def safe_inspect(term, opts \\ []) do
    limit = Keyword.get(opts, :limit, 1000)
    label = Keyword.get(opts, :label)

    inspected =
      try do
        inspect(term, limit: :infinity, printable_limit: :infinity, width: 80)
      rescue
        _ -> "#<inspect_failed>"
      end

    truncated = truncate_string(inspected, limit)

    if label do
      "#{label}: #{truncated}"
    else
      truncated
    end
  end

  # --- Private implementation ---

  defp log(level, message_fun, metadata) when is_function(message_fun, 0) do
    # Lazy evaluation - only call function if level is enabled
    if should_log?(level) do
      message = message_fun.()
      Logger.log(level, message, metadata)
    end

    :ok
  end

  defp log(level, message, metadata) when is_binary(message) do
    # For backward compatibility with eager strings
    if should_log?(level) do
      Logger.log(level, message, metadata)
    end

    :ok
  end

  defp should_log?(level) do
    # Compare levels using Logger's comparison
    current_level = Application.get_env(:jido, :observability, [])[:log_level] || :info
    Logger.compare_levels(current_level, level) in [:lt, :eq]
  end

  defp truncate_string(str, limit) when is_binary(str) do
    if byte_size(str) > limit do
      binary_part(str, 0, limit) <> "...[truncated]"
    else
      str
    end
  end

  defp truncate_string(other, _limit) do
    inspect(other)
  end
end
```

### Key API Principles

1. **Lazy Evaluation**: All logging functions accept zero-arity functions that are only evaluated if the log level is enabled
2. **Safe Inspection**: Use `safe_inspect/2` for all data serialization in logs
3. **Truncation**: Never log unbounded data - always apply limits
4. **Redaction**: Always apply redaction to sensitive keys before logging

## Telemetry Event Taxonomy

All telemetry events must follow the namespace pattern:

```
[:jido, :domain, :operation, :lifecycle]
```

### Standard Event Prefixes

| Domain | Event Prefix | Description |
|--------|-------------|-------------|
| Core | `[:jido, :agent, :action, :run]` | Action execution |
| Core | `[:jido, :agent, :workflow, :step]` | Workflow step |
| Core | `[:jido, :agent, :async, :request]` | Async operation |
| LLM | `[:jido, :ai, :llm, :request]` | LLM API call |
| LLM | `[:jido, :ai, :llm, :response]` | LLM response |
| LLM | `[:jido, :ai, :tool, :invoke]` | Tool invocation |
| Signal | `[:jido, :signal, :dispatch]` | Signal dispatch |
| Signal | `[:jido, :signal, :process]` | Signal processing |

### Event Lifecycle Suffixes

All spans emit three events:

- `[:start]` - Emitted when operation begins
- `[:stop]` - Emitted on successful completion
- `[:exception]` - Emitted on error/exception

### Measurements

Standard measurements across events:

| Measurement | Type | Description |
|-------------|------|-------------|
| `:system_time` | integer | Start timestamp (nanoseconds) |
| `:duration` | integer | Elapsed time (nanoseconds) |
| `:count` | integer | Item count where applicable |
| `:size_bytes` | integer | Payload size in bytes |

### Metadata Namespace

Standard metadata keys:

| Key | Description | Example |
|-----|-------------|---------|
| `:agent_id` | Unique agent identifier | `"agent_abc123"` |
| `:action` | Action name | `"search_tool"` |
| `:step` | Workflow step identifier | `"plan"` |
| `:model` | LLM model name | `"claude-3-opus"` |
| `:signal_type` | Signal type | `"user_message"` |
| `:jido_trace_id` | Distributed trace ID | `"trace_abc123"` |
| `:jido_span_id` | Current span ID | `"span_def456"` |
| `:jido_parent_span_id` | Parent span ID | `"span_abc123"` |
| `:jido_causation_id` | Causation signal ID | `"sig_xyz789"` |

## Redaction Policy

The following keys are **always redacted** in all logs and telemetry metadata:

- `api_key`
- `api_secret`
- `token`
- `access_token`
- `refresh_token`
- `password`
- `secret`
- `authorization`
- `auth_header`
- `private_key`
- `credential`

### Automatic Redaction

```elixir
# Automatically redacted
%{api_key: "sk-12345", user: "alice"}
# Logs as: %{api_key: "[REDACTED]", user: "alice"}
```

### Manual Redaction

Use `Jido.Observe.redact/2` for values that should be conditionally redacted:

```elixir
Jido.Observe.redact(sensitive_value, force_redact: true)
```

### Nested Redaction

Redaction applies recursively to nested maps and lists:

```elixir
%{
  config: %{
    api_key: "secret",  # Redacted
    timeout: 5000       # Preserved
  },
  tokens: ["token1", "token2"]  # Redacted if key matches
}
```

## Truncation Policy

Default truncation limits:

| Data Type | Default Limit | Config Key |
|-----------|---------------|------------|
| Log message | 1000 chars | `log_message_limit` |
| Inspect output | 1000 chars | `inspect_limit` |
| Binary/string | 500 bytes | `binary_limit` |
| List items | 50 items | `list_limit` |
| Map keys | 50 keys | `map_key_limit` |

## Lazy Logging Patterns

### ❌ Bad: Eager Interpolation

```elixir
# DON'T DO THIS - Always evaluates large_data
Logger.info("Processing: #{inspect(large_data)}")

# DON'T DO THIS - Always calls expensive_function
Logger.debug("Result: #{expensive_function()}")
```

### ✅ Good: Lazy Function

```elixir
# DO THIS - Only evaluates if debug enabled
Jido.Observe.debug(fn ->
  "Processing: #{safe_inspect(large_data, limit: 500)}"
end)

# DO THIS - Function only called if level enabled
Jido.Observe.info(fn ->
  "Result: #{safe_inspect(expensive_function())}"
end)
```

### ✅ Good: Threshold-Based

```elixir
# For data that might be large, always truncate
Jido.Observe.info(fn ->
  "API response: #{safe_inspect(response, limit: 200)}"
end)
```

## Configuration

### Default Configuration

```elixir
# config/config.exs
config :jido, :observability,
  log_level: :info,
  redact_sensitive: true,
  debug_events: :off,
  log_message_limit: 1000,
  inspect_limit: 1000,
  tracer: Jido.Observe.NoopTracer,
  tracer_failure_mode: :warn

# config/dev.exs
config :jido, :observability,
  log_level: :debug,
  redact_sensitive: false,
  debug_events: :all

# config/prod.exs
config :jido, :observability,
  log_level: :warning,
  redact_sensitive: true,
  debug_events: :off
```

### Test Configuration

```elixir
# config/test.exs
config :jido, :observability,
  log_level: :error,  # Minimize test noise
  redact_sensitive: false,  # Allow inspection in tests
  debug_events: :off
```

## CI Guard: Lazy Logging Enforcement

A lightweight CI check prevents eager interpolated logging:

```bash
# scripts/check_lazy_logging.sh
# See scripts/check_lazy_logging.sh for implementation
```

The CI guard catches patterns like:

```elixir
Logger.info("foo: #{bar}")        # ❌ Caught
Logger.debug("data: #{inspect(x)}")  # ❌ Caught
```

And allows:

```elixir
Logger.info(fn -> "foo: #{bar}" end)  # ✅ Allowed
Jido.Observe.info(fn -> ... end)     # ✅ Allowed
```

## Migration Guide for jido_* Repos

1. **Copy the helper API** - Copy the canonical API module above into your repo
2. **Add CI guard** - Copy `scripts/check_lazy_logging.sh` to your repo
3. **Update existing logs** - Replace `Logger.*` calls with lazy equivalents
4. **Add safe_inspect** - Replace `inspect/1` calls with `safe_inspect/2`
5. **Apply redaction** - Ensure sensitive keys are redacted before logging
6. **Update tests** - Tighten test-time logger defaults to minimize noise

## Best Practices

### DO:

- Use lazy logging functions for any non-trivial computation
- Use `safe_inspect/2` for all data serialization
- Apply truncation limits to all logged data
- Redact sensitive keys automatically
- Include trace IDs in all async contexts
- Use telemetry spans for measurable operations
- Set `log_level: :error` in test configuration

### DON'T:

- Use `Logger.info/1` with interpolated strings
- Log full params/context on hot paths
- Log at `:info` or `:debug` in high-frequency operations
- Include raw API responses in logs without truncation
- Log personally identifiable information (PII)
- Use `inspect/1` on potentially large data structures

## Example: Full Migration

Before:

```elixir
def process_request(params) do
  Logger.info("Processing request: #{inspect(params)}")
  result = do_work(params)
  Logger.debug("Got result: #{inspect(result)}")
  result
end
```

After:

```elixir
def process_request(params) do
  # Log only identifying info, not full params
  Jido.Observe.info(fn ->
    "Processing request: #{params.request_id}"
  end)

  result = do_work(params)

  # Truncate and use lazy evaluation
  Jido.Observe.debug(fn ->
    "Got result: #{safe_inspect(result, limit: 200)}"
  end)

  result
end
```

## References

- `Jido.Observe` - Main observability facade
- `Jido.Observe.Log` - Threshold-based logging
- `Jido.Observe.Config` - Configuration resolution
- `scripts/check_lazy_logging.sh` - CI guard script
