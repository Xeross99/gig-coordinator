class CleanupIndexesAndAddFunctionalUnique < ActiveRecord::Migration[8.1]
  def change
    remove_index :participations, :event_id, name: "index_participations_on_event_id"
    remove_index :messages,       :event_id, name: "index_messages_on_event_id"
    remove_index :host_managers,  :user_id,  name: "index_host_managers_on_user_id"
    remove_index :host_blocks,    :user_id,  name: "index_host_blocks_on_user_id"

    add_index :users, "LOWER(first_name), last_name", unique: true,
              name: "index_users_on_lower_first_name_and_last_name"
    add_index :hosts, "LOWER(first_name), last_name", unique: true,
              name: "index_hosts_on_lower_first_name_and_last_name"
  end
end
