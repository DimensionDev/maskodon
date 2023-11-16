class AddNewFieldStatuses < ActiveRecord::Migration[7.0]
  def change
    add_column :statuses, :cid, :string
end
end
