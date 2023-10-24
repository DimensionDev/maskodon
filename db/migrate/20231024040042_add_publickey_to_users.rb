class AddPublickeyToUsers < ActiveRecord::Migration[7.0]
  def change

        add_column :users, :public_key, :string

  end
end
