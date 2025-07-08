class CreateGames < ActiveRecord::Migration[7.2]
  def change
    create_table :games do |t|
      t.integer :board_size, null: false, default: 20
      t.integer :elements_per_type, null: false, default: 50
      t.text :board, null: false
      t.integer :current_round, null: false, default: 0
      t.string :game_state, null: false, default: 'running'

      t.timestamps
    end
    
    add_index :games, :game_state
  end
end 