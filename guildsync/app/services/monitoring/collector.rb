# frozen_string_literal: true

module Monitoring
  # Collects system and application metrics for the admin System Monitoring dashboard.
  # Each metric is rescued so one failure does not break the rest.
  class Collector
    class << self
      def call
        {
          memory: memory_metrics,
          cpu: cpu_metrics,
          disk: disk_metrics,
          sidekiq: sidekiq_metrics,
          puma: puma_metrics,
          database: database_metrics,
          collected_at: Time.current.iso8601
        }
      end

      private

      def memory_metrics
        {
          process_rss_mb: process_rss_mb,
          system_total_mb: system_memory_total_mb,
          system_used_mb: system_memory_used_mb,
          system_available_mb: system_memory_available_mb
        }
      rescue => e
        { error: e.message }
      end

      def process_rss_mb
        rss_kb = nil
        if File.readable?("/proc/self/status")
          content = File.read("/proc/self/status")
          m = content.match(/VmRSS:\s+(\d+)\s+kB/)
          rss_kb = m[1].to_i if m
        end
        rss_kb ||= begin
          out = `ps -o rss= -p #{Process.pid} 2>/dev/null`.strip
          out.present? ? out.to_i : nil
        end
        rss_kb ? (rss_kb / 1024.0).round(2) : nil
      end

      def system_memory_total_mb
        if File.readable?("/proc/meminfo")
          content = File.read("/proc/meminfo")
          m = content.match(/MemTotal:\s+(\d+)\s+kB/)
          return (m[1].to_i / 1024.0).round(2) if m
        end
        # macOS: vm_stat doesn't give MemTotal; skip system total on non-Linux
        nil
      end

      def system_memory_used_mb
        return nil unless File.readable?("/proc/meminfo")
        content = File.read("/proc/meminfo")
        total = content.match(/MemTotal:\s+(\d+)\s+kB/)&.[](1)&.to_i
        avail = content.match(/MemAvailable:\s+(\d+)\s+kB/)&.[](1)&.to_i
        return nil unless total && avail
        ((total - avail) / 1024.0).round(2)
      end

      def system_memory_available_mb
        return nil unless File.readable?("/proc/meminfo")
        m = File.read("/proc/meminfo").match(/MemAvailable:\s+(\d+)\s+kB/)
        m ? (m[1].to_i / 1024.0).round(2) : nil
      end

      def cpu_metrics
        load_avg = nil
        if File.readable?("/proc/loadavg")
          load_avg = File.read("/proc/loadavg").split(/\s+/).first(3).map(&:to_f)
        else
          out = `sysctl -n vm.loadavg 2>/dev/null`.strip
          load_avg = out.scan(/[\d.]+/).first(3).map(&:to_f) if out.present?
        end
        { load_average: load_avg || [] }
      rescue => e
        { error: e.message }
      end

      def disk_metrics
        out = `df -k . 2>/dev/null`.strip
        return { error: "df unavailable" } if out.blank?
        lines = out.lines.map(&:split)
        return { error: "parse failed" } if lines.size < 2
        # Last line is usually the mount for .
        row = lines.last
        total_k = row[1].to_i
        used_k = row[2].to_i
        avail_k = row[3].to_i
        {
          total_mb: (total_k / 1024.0).round(2),
          used_mb: (used_k / 1024.0).round(2),
          available_mb: (avail_k / 1024.0).round(2),
          used_percent: total_k.positive? ? ((used_k.to_f / total_k) * 100).round(1) : nil
        }
      rescue => e
        { error: e.message }
      end

      def sidekiq_metrics
        return { error: "Sidekiq not loaded" } unless defined?(Sidekiq)
        stats = Sidekiq::Stats.new
        {
          processed: stats.processed,
          failed: stats.failed,
          busy: stats.workers_size,
          scheduled_size: stats.scheduled_size,
          retry_size: stats.retry_size,
          dead_size: stats.dead_size,
          enqueued: stats.enqueued,
          queues: Sidekiq::Queue.all.map { |q| { name: q.name, size: q.size } }
        }
      rescue => e
        { error: e.message }
      end

      def puma_metrics
        # Puma doesn't expose a simple API; report process info.
        # Puma 6+ may expose options as Puma::UserFileDefaultOptions (no Hash#dig).
        workers =
          if defined?(Puma) && Puma.respond_to?(:cli_config)
            puma_worker_count
          else
            1
          end
        {
          workers: workers,
          phase: $0.to_s.include?("puma") ? "running" : "unknown"
        }
      rescue => e
        { error: e.message }
      end

      def puma_worker_count
        opts = Puma.cli_config&.options
        return 1 if opts.nil?

        raw =
          if opts.respond_to?(:dig)
            opts.dig(:workers)
          elsif opts.respond_to?(:[])
            opts[:workers]
          elsif opts.respond_to?(:to_h)
            opts.to_h[:workers]
          end

        w = raw.nil? ? 1 : raw.to_i
        w.positive? ? w : 1
      end

      def database_metrics
        pool = ActiveRecord::Base.connection_pool
        {
          pool_size: pool.size,
          connections: pool.connections.size,
          in_use: pool.connections.count(&:in_use?)
        }
      rescue => e
        { error: e.message }
      end
    end
  end
end
