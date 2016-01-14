class CommentsController < ApplicationController
  def create
    @comment = Comment.new(:author => params["author"], :comment => params["comment"], :migration_id => params["migration_id"])
    @comment.save

    return render :nothing => true, :status => :bad_request unless @comment.valid?

    MigrationMailer.migration_comment(@comment).deliver_now
    render :nothing => true
  end

  # coming soon
  def delete
  end
end
