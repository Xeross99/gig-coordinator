class WebPushPool
  # Musi być >= WebPushNotifier::CONCURRENT_SENDS — efektywna równoległość
  # wysyłki to min(wątki, połączenia w puli) per host serwera push.
  POOL_SIZE = 16
  KEEP_ALIVE_TIMEOUT = 30
  OPEN_TIMEOUT = 5
  READ_TIMEOUT = 10

  CONNECTION_ERRORS = [
    Errno::ECONNRESET, Errno::EPIPE, Errno::ECONNREFUSED,
    IOError, OpenSSL::SSL::SSLError
  ].freeze

  class << self
    def instance
      @instance ||= new
    end

    def with_connection(uri, &block)
      instance.with_connection(uri, &block)
    end

    def prewarm!
      instance.prewarm!
    end

    def shutdown!
      instance.shutdown!
    end

    def reset!
      @instance&.shutdown!
      @instance = nil
    end
  end

  def initialize
    @pools = Concurrent::Map.new
  end

  def with_connection(uri)
    pool = pool_for(uri.host, uri.port)
    conn = pool.pop
    retried = false
    begin
      conn = ensure_started(conn, uri.host, uri.port)
      yield conn
    rescue *CONNECTION_ERRORS
      raise if retried
      retried = true
      conn.finish rescue nil
      conn = build_connection(uri.host, uri.port)
      conn.start
      retry
    ensure
      pool.push(conn)
    end
  end

  def prewarm!
    hosts = PushSubscription.pluck(:endpoint).filter_map { |ep|
      uri = URI.parse(ep)
      [ uri.host, uri.port ] if uri.host
    }.uniq

    hosts.each do |host, port|
      Thread.new do
        pool_for(host, port)
      rescue => e
        Rails.logger.warn("WebPushPool prewarm #{host}:#{port} failed: #{e.message}")
      end
    end
  end

  def shutdown!
    @pools.each_value do |pool|
      POOL_SIZE.times do
        conn = pool.pop(true) rescue nil
        conn&.finish rescue nil
      end
    end
    @pools.clear
  end

  private

  def pool_for(host, port)
    key = "#{host}:#{port}"
    @pools.compute_if_absent(key) { build_pool(host, port) }
  end

  def build_pool(host, port)
    queue = Queue.new
    POOL_SIZE.times do
      conn = build_connection(host, port)
      begin
        conn.start
      rescue => e
        Rails.logger.warn("WebPushPool: connect #{host}:#{port} failed: #{e.message}")
      end
      queue.push(conn)
    end
    queue
  end

  def build_connection(host, port)
    http = Net::HTTP.new(host, port)
    http.use_ssl = true
    http.keep_alive_timeout = KEEP_ALIVE_TIMEOUT
    http.open_timeout = OPEN_TIMEOUT
    http.read_timeout = READ_TIMEOUT
    http
  end

  def ensure_started(conn, host, port)
    return conn if conn.started?
    conn.start
    conn
  rescue
    conn.finish rescue nil
    fresh = build_connection(host, port)
    fresh.start
    fresh
  end
end
