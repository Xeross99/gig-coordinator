class MakeExpoPushTokensPolymorphic < ActiveRecord::Migration[8.1]
  def change
    add_column :expo_push_tokens, :tokenable_type, :string
    add_column :expo_push_tokens, :tokenable_id, :integer

    reversible do |dir|
      dir.up do
        execute "UPDATE expo_push_tokens SET tokenable_type = 'User', tokenable_id = user_id"
      end
    end

    remove_reference :expo_push_tokens, :user, foreign_key: true
    add_index :expo_push_tokens, [ :tokenable_type, :tokenable_id ]
  end
end
