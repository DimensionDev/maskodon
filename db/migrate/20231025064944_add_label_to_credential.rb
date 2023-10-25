class AddLabelToCredential < ActiveRecord::Migration[7.0]
  def change
    add_column :credentials, :label, :string, unique: true,null: false
  end
end
