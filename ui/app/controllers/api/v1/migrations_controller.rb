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

      def offer
        @migration = Migration.find(params[:id])
        if @migration.offer!
          @migration.reload
        end
        render json: @migration
      end

      def unpin_run_host
        @migration = Migration.find(params[:id])
        if @migration.unpin_run_host!
          @migration.reload
        end
        render json: @migration
      end

      def append_to_file
        migration_id = params[:migration_id].to_i
        file_type = params[:file_type].to_i
        contents = params[:contents]

        if !ShiftFile.file_types[:appendable].include?(file_type)
          return render json: {message: "File type not appendable"}, status: 400
        end

        begin
          shift_file = ShiftFile.find_or_create_by!(migration_id: migration_id, file_type: file_type)
        rescue ActiveRecord::RecordNotUnique
          return render json: {message: "Could not create new file because one already exists"}, status: 400
        end
        shift_file.contents = shift_file.contents.to_s + contents
        shift_file.save
        shift_file.contents = "Content omitted..." # content can be large, no value in returning it

        render json: shift_file
      end

      def write_file
        migration_id = params[:migration_id].to_i
        file_type = params[:file_type].to_i
        contents = params[:contents]

        if !ShiftFile.file_types[:writable].include?(file_type)
          return render json: {message: "File type not writable"}, status: 400
        end

        begin
          shift_file = ShiftFile.find_or_create_by!(migration_id: migration_id, file_type: file_type)
        rescue ActiveRecord::RecordNotUnique
          return render json: {message: "Could not create new file because one already exists"}, status: 400
        end
        shift_file.contents = contents
        shift_file.save
        shift_file.contents = "Content omitted..." # content can be large, no value in returning it

        render json: shift_file
      end

      def get_file
        migration_id = params[:migration_id].to_i
        file_type = params[:file_type].to_i

        shift_file = ShiftFile.find_by(migration_id: migration_id, file_type: file_type)
        if shift_file == nil
          return render json: {message: "File not found"}, status: 404
        end

        render json: shift_file
      end

      ## all the methods below this point are used only by the shift-client CLI right now ##

      def show
        begin
          @migration = Migration.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          return render json: {:status => 404, :errors => ["Migration not found."]}, :status => 404
        end

        render json: {:migration => @migration, :available_actions => available_actions}
      end

      def create
        @migration = Form::NewMigrationRequest.new(params)
        if @migration.save
          @migration = Migration.find(@migration.dao.id)
          return render json: {:migration => @migration, :available_actions => available_actions}
        else
          errors = []
          @migration.errors.full_messages.each do |e|
            errors << e + "."
          end
          return render json: {:status => 400, :errors => errors}, :status => 400
        end
      end

      def approve
        generic_step("approve", params[:approver], params[:runtype], params[:lock_version])
      end

      def unapprove
        generic_step("unapprove", params[:lock_version])
      end

      def start
        generic_step("start", params[:lock_version], params[:auto_run])
      end

      def enqueue
        generic_step("enqueue", params[:lock_version])
      end

      def dequeue
        generic_step("dequeue", params[:lock_version])
      end

      def pause
        generic_step("pause")
      end

      def rename
        generic_step("rename", params[:lock_version])
      end

      def resume
        generic_step("resume", params[:lock_version], params[:auto_run])
      end

      # since we already have a "def cancel" that the runner uses that is slightly different...
      def cancel_cli
        generic_step("cancel")
      end

      def destroy
        begin
          @migration = Migration.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          return render json: {:status => 404, :errors => ["Migration not found."]}, :status => 404
        end

        if @migration.delete!(params[:lock_version])
          send_notifications("migration id #{params[:id]} deleted from the CLI")
          return render json: {}, :status => 200
        else
          return render json: {:status => 400, :errors => generic_error_msg("delete")}, :status => 400
        end
      end

      private

      def generic_step(step, *extra_params)
        begin
          @migration = Migration.find(params[:id])
        rescue ActiveRecord::RecordNotFound
          return render json: {:status => 404, :errors => ["Migration not found."]}, :status => 404
        end

        # is the cluster already maxed out on running migrations? only relevant
        # for starting a migration
        maxed_out = false
        # make sure we don't allow approving a run type that shouldn't be allowed
        action_step = step == "approve" ? "#{step}_#{params[:runtype]}" : step
        if available_actions.map{|a| a.to_s == action_step }.any?
          succeeded, maxed_out = @migration.send("#{step.split('_')[0]}!", *extra_params)
          if succeeded
            @migration.reload
            step_past_tense = case step
            when "start" || "cancel"
              step + "ed"
            else
              step + "d"
            end
            send_notifications("migration id #{params[:id]} #{step_past_tense} from the CLI")
            return render json: {:migration => @migration, :available_actions => available_actions}
          end
        end

        render json: {:status => 400, :errors => generic_error_msg(step, maxed_out)}, :status => 400
      end

      def generic_error_msg(step, maxed_out = false)
        errors = []
        action_step = step == "approve" ? "#{step}_#{params[:runtype]}" : step
        errors << "Invalid action." unless available_actions.map{|a| a.to_s == action_step }.any?
        errors << "Incorrect lock_version supplied." unless params[:lock_version].to_i == @migration.lock_version
        errors << "Can't start migration because you are already running the maximum # of migrations "\
          "per cluster (#{Migration.parallel_run_limit})." if (step == "start" && maxed_out)
        return errors
      end

      def available_actions
        begin
          result = OscParser.new.parse @migration[:ddl_statement]
          run_action = Migration.types[:action][result[:action]]
        rescue
          run_action = Migration.types[:action][:alter]
        end

        a = @migration.authorized_actions(@migration.initial_runtype, run_action, true, true, true, true)
        # manually add support for this in the cli since we don't yet have full support in the ui.
        # remove this once you can enqueue a single migration in the ui
        a << :enqueue if @migration.status == 2
        return a
      end

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
