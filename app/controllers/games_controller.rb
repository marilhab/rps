class GamesController < ApplicationController
  def index
    @games = Game.order(created_at: :desc).limit(10)
  end

  def show
    @game = Game.find(params[:id])
    @counts = @game.count_elements
    @kill_counts = @game.kill_counts || { 'rock' => 0, 'paper' => 0, 'scissors' => 0 }
  end

  def new
    @game = Game.new
  end

  def create
    @game = Game.new(game_params)
    
    if @game.save
      redirect_to @game, notice: 'Game created successfully!'
    else
      render :new, status: :unprocessable_entity
    end
  end

  def next_round
    @game = Game.find(params[:id])
    
    if @game.next_round
      render json: {
        board: @game.board,
        current_round: @game.current_round,
        counts: @game.count_elements,
        kill_counts: @game.kill_counts,
        game_over: @game.game_over?,
        winner: @game.winner
      }
    else
      render json: { error: 'Game is already over' }, status: :unprocessable_entity
    end
  end

  def auto_play
    @game = Game.find(params[:id])
    
    # Check if game is already over
    if @game.game_over?
      redirect_to @game, notice: "Game already completed! Winner: #{@game.winner&.titleize}"
      return
    end
    
    # Run the game to completion with a safety limit
    max_rounds = 1000  # Prevent infinite loops
    rounds_played = 0
    
    until @game.game_over? || rounds_played >= max_rounds
      @game.next_round
      rounds_played += 1
    end
    
    if rounds_played >= max_rounds
      redirect_to @game, alert: "Game reached maximum rounds (#{max_rounds}). Current state: #{@game.count_elements}"
    else
      redirect_to @game, notice: "Game completed in #{rounds_played} rounds! Winner: #{@game.winner&.titleize}"
    end
  end

  private

  def game_params
    params.require(:game).permit(:board_size, :elements_per_type)
  end
end 