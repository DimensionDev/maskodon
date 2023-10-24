class AddNewFieldToMediaAttachment < ActiveRecord::Migration[7.0]
  def change
    add_column :media_attachments, :file_cid, :string
  end
end
