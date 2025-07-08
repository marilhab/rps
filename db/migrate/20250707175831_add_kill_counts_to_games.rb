class AddKillCountsToGames < ActiveRecord::Migration[7.2]
  def change
    add_column :games, :kill_counts, :text
  end
end
