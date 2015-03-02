# Copyright (c) 2009-2012 VMware, Inc.

module VSphereCloud
  class Resources

    # Resource Scorer.
    class Scorer

      # Creates a new Scorer given a cluster and requested memory and storage.
      #
      # @param [Bosh::Clouds::Config] config the config.
      # @param [Integer] memory required memory.
      # @param [Cluster] cluster_with_disks requested cluster.
      # @param [Array<Integer>] ephemeral list of required ephemeral disk sizes.
      def initialize(config, cluster_with_disks, memory, ephemeral)
        @cluster = cluster_with_disks.cluster
        @persistent = cluster_with_disks.disks.map(&:size_in_mb)

        @logger = config.logger
        @memory = memory
        @ephemeral = ephemeral

        @free_memory = @cluster.free_memory

        @free_ephemeral = []
        @cluster.ephemeral_datastores.each_value do |datastore|
          @free_ephemeral << datastore.free_space
        end

        @free_persistent = []
        @cluster.persistent_datastores.each_value do |datastore|
          @free_persistent << datastore.free_space
        end

        @free_shared = []
        @cluster.shared_datastores.each_value do |datastore|
          @free_shared << datastore.free_space
        end
      end

      # Run the scoring function and return the placement score for the required
      # resources.
      #
      # @return [Integer] score.
      def score
        min_ephemeral = @ephemeral
        min_persistent = @persistent.min
        min_shared = min_ephemeral
        if !min_persistent.nil? && min_persistent < min_shared
          min_shared = min_persistent
        end

        # Filter out any datastores that are below the min threshold
        filter(@free_ephemeral, min_ephemeral + DISK_THRESHOLD)
        filter(@free_shared, min_shared + DISK_THRESHOLD)
        unless @persistent.empty?
          filter(@free_persistent, min_persistent + DISK_THRESHOLD)
        end

        count = 0
        loop do
          @free_memory -= @memory
          if @free_memory < MEMORY_THRESHOLD
            @logger.debug("#{@cluster.name} memory bound")
            break
          end

          consumed = consume_disk(@free_ephemeral, @ephemeral, min_ephemeral)
          unless consumed
            unless consume_disk(@free_shared, @ephemeral, min_shared)
              @logger.debug("#{@cluster.name} ephemeral disk bound")
              break
            end
          end

          unless @persistent.empty?
            consumed_all = false
            @persistent.each do |size|
              consumed = consume_disk(@free_persistent, size, min_persistent)
              unless consumed
                consumed = consume_disk(@free_shared, size, min_shared)
                unless consumed
                  consumed_all = true
                  @logger.debug("#{@cluster.name} persistent disk bound")
                  break
                end
              end
            end
            break if consumed_all
          end

          count += 1
        end

        count
      end

      private

      # Filter out datastores from the pool that are below the free space
      # threshold.
      #
      # @param [Array<Integer>] pool datastore pool.
      # @param [Integer] threshold free space threshold
      # @return [Array<Integer>] filtered pool.
      def filter(pool, threshold)
        pool.delete_if { |size| size < threshold }
      end

      # Consumes disk space from a datastore pool.
      #
      # @param [Array<Integer>] pool datastore pool.
      # @param [Integer] size requested disk size.
      # @param [Integer] min requested disk size, so the datastore can be
      #   removed from the pool if it falls below this threshold.
      # @return [true, false] boolean indicating that the disk space was
      #   consumed.
      def consume_disk(pool, size, min)
        unless pool.empty?
          pool.sort! { |a, b| b <=> a }
          if pool[0] >= size + DISK_THRESHOLD
            pool[0] -= size
            pool.delete_at(0) if pool[0] < min + DISK_THRESHOLD
            return true
          end
        end
        false
      end
    end
  end
end
