class AddNewFieldTostatuses < ActiveRecord::Migration[7.0]
  def up
    add_column :statuses, :cid, :string
  end
end
