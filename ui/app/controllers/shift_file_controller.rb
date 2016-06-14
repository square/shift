class ShiftFileController < ApplicationController
  def show
    migration_id = params[:migration_id]
    file_type = params[:file_type]
    shift_file = ShiftFile.where(migration_id: migration_id, file_type: file_type).take
    if shift_file == nil 
      render text: "File not found", layout: false, content_type: "text/plain", status: 404
    else
      render text: shift_file.contents, layout: false, content_type: "text/plain"
    end
  end
end
