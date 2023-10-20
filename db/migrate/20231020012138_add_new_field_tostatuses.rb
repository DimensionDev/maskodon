class AddNewFieldTostatuses < ActiveRecord::Migration[7.0]
  def change
    #remove_column :statuses, :cid, :bigint
    safety_assured { remove_column :statuses, :cid, :bigint }
    add_column :statuses, :cid, :string
  end
end
