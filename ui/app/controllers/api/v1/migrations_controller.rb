module Api
  module V1
    class MigrationsController < ApiController
      def staged
        @migrations = Migration.migrations_by_state(:machine, order: "updated_at",
          additional_filters: {:staged => true})

        map = {
          :stm => 'ddl_statement',
          :table => 'table',
          :mode => 'mode',
          :action => 'action',
        }

        # reject migs with bad ddl, unless they are on the cancel step
        filtered = @migrations.reject do |mig|
          mig.parsed[:error] && mig.status != Migration.status_groups[:canceled]
        end

        result = filtered.map do |mig|
          dict = mig.as_json
          # if runtype is still undecided for some reason, set it to 'long' by defualt (unless we
          # forsure know that it's short)
          if mig.runtype == Migration.types[:run][:undecided]
            parsed_runtype = mig.parsed[:run]
            dict['runtype'] = Migration.types[:run][
              (parsed_runtype == :maybeshort || parsed_runtype == :maybenocheckalter) ? :long : parsed_runtype
            ]
          end
          # update the json with the parsed ddl, the table name (parsed from the ddl), and the
          # mode/action enum values
          map.each do |k, v|
            dict[v] =
              if Migration.types.has_key? k
                Migration.types[k][mig.parsed[k]]
              else
                mig.parsed[k]
              end
          end

          # update the json with the host and port for each migration
          dict[:host] = mig.cluster.rw_host || next
          dict[:port] = mig.cluster.port || next

          dict
        end

        render json: result.compact.take(Migration.unstage_limit)
      end

      def show
        @migration = Migration.find(params[:id])
        render json: @migration
      end

      def unstage
        @migration = Migration.find(params[:id])
        if @migration.unstage!
          @migration.reload
          Notifier.notify("migration id #{params[:id]} unstaged from the API")
          render json: @migration
        else
          render json: {}
        end
      end

      def next_step
        @migration = Migration.find(params[:id])
        if @migration.next_step_machine!
          @migration.reload
          send_notifications("migration id #{params[:id]} moved to status=#{@migration.status} from the API")
        end
        render json: @migration
      end

      def update
        @migration = Migration.find(params[:id])
        @migration.reload if @migration.update_attributes(migration_params)
        render json: @migration
      end

      def complete
        @migration = Migration.find(params[:id])
        if @migration.complete!
          @migration.reload
          send_notifications("migration id #{params[:id]} completed from the API")
        end
        render json: @migration
      end

      def cancel
        @migration = Migration.find(params[:id])
        if @migration.cancel!
          @migration.reload
          send_notifications("migration id #{params[:id]} canceled from the API")
        end
        render json: @migration
      end

      def fail
        @migration = Migration.find(params[:id])
        if @migration.fail!(params[:error_message])
          @migration.reload
          send_notifications("migration id #{params[:id]} failed from the API")
        end
        render json: @migration
      end

      def error
        @migration = Migration.find(params[:id])
        if @migration.error!(params[:error_message])
          @migration.reload
          send_notifications("migration id #{params[:id]} errored out from the API")
        end
        render json: @migration
      end

      private

      def migration_params
        params.permit(:table_rows_start, :table_rows_end, :table_size_start, :table_size_end,
                      :index_size_start, :index_size_end, :work_directory, :copy_percentage, :run_host)
      end

      def send_notifications(message)
        Notifier.notify(message)
        MigrationMailer.migration_status_change(@migration).deliver_now
      end
    end
  end
end
