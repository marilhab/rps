class Game < ApplicationRecord
  validates :board_size, presence: true, numericality: { greater_than: 0 }
  validates :elements_per_type, presence: true, numericality: { greater_than: 0 }
  
  serialize :board, coder: JSON
  serialize :kill_counts, coder: JSON
  
  before_create :initialize_board
  
  def initialize_board
    self.board = generate_initial_board
    self.current_round = 0
    self.game_state = 'running'
    self.kill_counts = { 'rock' => 0, 'paper' => 0, 'scissors' => 0 }
  end
  
  def generate_initial_board
    board_size = self.board_size || 20
    elements_per_type = self.elements_per_type || 50
    
    # Create empty board
    board = Array.new(board_size) { Array.new(board_size, nil) }
    
    # Place elements randomly
    elements = []
    elements_per_type.times { elements << 'rock' }
    elements_per_type.times { elements << 'paper' }
    elements_per_type.times { elements << 'scissors' }
    elements.shuffle!
    
    elements.each do |element|
      placed = false
      until placed
        x = rand(board_size)
        y = rand(board_size)
        if board[y][x].nil?
          board[y][x] = element
          placed = true
        end
      end
    end
    
    board
  end
  
  def count_elements
    counts = { 'rock' => 0, 'paper' => 0, 'scissors' => 0 }
    board.each do |row|
      row.each do |cell|
        counts[cell] += 1 if cell
      end
    end
    counts
  end
  
  def game_over?
    counts = count_elements
    counts.values.count { |count| count > 0 } <= 1
  end
  
  def winner
    return nil unless game_over?
    counts = count_elements
    counts.key(counts.values.max)
  end
  
  def next_round
    return false if game_over?
    
    # Store current board to check if anything changed
    old_board = board.map(&:dup)
    
    # Track planned moves to handle conflicts
    planned_moves = {}
    conflicts = {}
    
    # First pass: plan all moves
    board_size.times do |y|
      board_size.times do |x|
        current_element = board[y][x]
        next unless current_element
        
        # Find best move for this element
        best_move = find_best_move(x, y, current_element)
        if best_move
          new_x, new_y = best_move
          target_element = board[new_y][new_x]
          
          # Check if we're moving toward prey or away from predator
          if target_element.nil? || can_win(current_element, target_element)
            target_key = "#{new_x},#{new_y}"
            if planned_moves[target_key]
              # Conflict detected - both elements want the same cell
              conflicts[target_key] = [planned_moves[target_key], [x, y, current_element]]
            else
              planned_moves[target_key] = [x, y, current_element]
            end
          else
            # We can't win this move, but maybe we should still move to avoid predators
            # Check if there are predators nearby
            predators_nearby = check_for_predators(x, y, current_element)
            
            if predators_nearby && target_element.nil?
              # Move to empty space to escape predators
              target_key = "#{new_x},#{new_y}"
              if planned_moves[target_key]
                planned_moves["#{x},#{y}"] = [x, y, current_element]
              else
                planned_moves[target_key] = [x, y, current_element]
              end
            else
              # Try to find a better escape route
              escape_move = find_escape_move(x, y, current_element)
              if escape_move
                new_x, new_y = escape_move
                target_key = "#{new_x},#{new_y}"
                if planned_moves[target_key]
                  planned_moves["#{x},#{y}"] = [x, y, current_element]
                else
                  planned_moves[target_key] = [x, y, current_element]
                end
              else
                # Stay in place
                planned_moves["#{x},#{y}"] = [x, y, current_element]
              end
            end
          end
        else
          # Try to move to any empty space to avoid getting stuck
          random_empty = find_random_empty_space(x, y)
          if random_empty
            new_x, new_y = random_empty
            target_key = "#{new_x},#{new_y}"
            if planned_moves[target_key]
              # Conflict - stay in place
              planned_moves["#{x},#{y}"] = [x, y, current_element]
            else
              planned_moves[target_key] = [x, y, current_element]
            end
          else
            # Stay in place
            planned_moves["#{x},#{y}"] = [x, y, current_element]
          end
        end
      end
    end
    
    # Resolve conflicts
    conflicts.each do |target_key, elements|
      # In case of conflict, the stronger element wins
      element1 = elements[0][2]
      element2 = elements[1][2]
      
      if can_win(element1, element2)
        # Element 1 wins, element 2 stays in place
        planned_moves[target_key] = elements[0]
        planned_moves["#{elements[1][0]},#{elements[1][1]}"] = elements[1]
        # Increment kill counter
        self.kill_counts[element1] += 1
      elsif can_win(element2, element1)
        # Element 2 wins, element 1 stays in place
        planned_moves[target_key] = elements[1]
        planned_moves["#{elements[0][0]},#{elements[0][1]}"] = elements[0]
        # Increment kill counter
        self.kill_counts[element2] += 1
      else
        # Tie - both stay in place
        planned_moves["#{elements[0][0]},#{elements[0][1]}"] = elements[0]
        planned_moves["#{elements[1][0]},#{elements[1][1]}"] = elements[1]
      end
    end
    
    # Second pass: create new board from resolved moves
    new_board = Array.new(board_size) { Array.new(board_size, nil) }
    planned_moves.each do |key, (x, y, element)|
      new_board[y][x] = element
    end
    
    self.board = new_board
    self.current_round += 1
    self.game_state = 'finished' if game_over?
    save!
    
    # Check if board changed - if not, force some random movements
    if board_unchanged?(old_board) && !game_over?
      force_random_movements
      save!
    end
    
    true
  end
  
  private
  
  def find_best_move(x, y, element)
    directions = [
      [-1, -1], [-1, 0], [-1, 1],
      [0, -1],           [0, 1],
      [1, -1],  [1, 0],  [1, 1]
    ]
    
    # Shuffle directions to add randomness and prevent patterns
    directions.shuffle!
    
    best_score = -1
    best_move = nil
    
    # First, look for immediate prey (adjacent cells)
    directions.each do |dx, dy|
      new_x = x + dx
      new_y = y + dy
      
      next if new_x < 0 || new_x >= board_size || new_y < 0 || new_y >= board_size
      
      target_element = board[new_y][new_x]
      score = calculate_move_score(element, target_element)
      
      # Add small random factor to break ties and prevent patterns
      score += rand(0.1)
      
      if score > best_score
        best_score = score
        best_move = [new_x, new_y]
      end
    end
    
    # If no good immediate move found, look for prey within 2 steps
    if best_score < 5 && best_move
      directions.each do |dx, dy|
        new_x = x + dx
        new_y = y + dy
        
        next if new_x < 0 || new_x >= board_size || new_y < 0 || new_y >= board_size
        
        # Check if moving here would put us closer to prey
        if board[new_y][new_x].nil?
          # Look around this potential move for prey
          prey_found = false
          directions.each do |dx2, dy2|
            check_x = new_x + dx2
            check_y = new_y + dy2
            
            next if check_x < 0 || check_x >= board_size || check_y < 0 || check_y >= board_size
            
            if can_win(element, board[check_y][check_x])
              prey_found = true
              break
            end
          end
          
          if prey_found
            score = 7 # Good strategic position
            score += rand(0.1)
            
            if score > best_score
              best_score = score
              best_move = [new_x, new_y]
            end
          end
        end
      end
    end
    
    best_move
  end
  
  def calculate_move_score(element, target_element)
    return 3 if target_element.nil? # Empty space is okay
    
    if can_win(element, target_element)
      # Actively seek prey - this is the highest priority
      return 10
    elsif can_win(target_element, element)
      # Avoid predators - this is the lowest priority
      return 0
    else
      # Same type - neutral, slight preference for movement
      return 2
    end
  end
  
  def can_win(attacker, defender)
    case attacker
    when 'rock'
      defender == 'scissors'
    when 'paper'
      defender == 'rock'
    when 'scissors'
      defender == 'paper'
    else
      false
    end
  end
  
  def is_predator(predator, prey)
    can_win(predator, prey)
  end
  
  def check_for_predators(x, y, element)
    directions = [
      [-1, -1], [-1, 0], [-1, 1],
      [0, -1],           [0, 1],
      [1, -1],  [1, 0],  [1, 1]
    ]
    
    directions.each do |dx, dy|
      check_x = x + dx
      check_y = y + dy
      
      next if check_x < 0 || check_x >= board_size || check_y < 0 || check_y >= board_size
      
      neighbor = board[check_y][check_x]
      return true if neighbor && is_predator(neighbor, element)
    end
    
    false
  end
  
  def find_escape_move(x, y, element)
    directions = [
      [-1, -1], [-1, 0], [-1, 1],
      [0, -1],           [0, 1],
      [1, -1],  [1, 0],  [1, 1]
    ]
    
    directions.shuffle!
    
    directions.each do |dx, dy|
      new_x = x + dx
      new_y = y + dy
      
      next if new_x < 0 || new_x >= board_size || new_y < 0 || new_y >= board_size
      
      # Only move to empty spaces when escaping
      if board[new_y][new_x].nil?
        # Check if this move would put us away from predators
        predators_after_move = check_for_predators(new_x, new_y, element)
        if !predators_after_move
          return [new_x, new_y]
        end
      end
    end
    
    # If no good escape found, just find any empty space
    find_random_empty_space(x, y)
  end
  
  def find_random_empty_space(x, y)
    directions = [
      [-1, -1], [-1, 0], [-1, 1],
      [0, -1],           [0, 1],
      [1, -1],  [1, 0],  [1, 1]
    ]
    
    # Shuffle to make it random
    directions.shuffle!
    
    directions.each do |dx, dy|
      new_x = x + dx
      new_y = y + dy
      
      next if new_x < 0 || new_x >= board_size || new_y < 0 || new_y >= board_size
      
      if board[new_y][new_x].nil?
        return [new_x, new_y]
      end
    end
    
    nil
  end
  
  def board_unchanged?(old_board)
    board.each_with_index do |row, y|
      row.each_with_index do |cell, x|
        return false if cell != old_board[y][x]
      end
    end
    true
  end
  
  def force_random_movements
    # Force some random movements to break stalemates
    elements_to_move = []
    
    board.each_with_index do |row, y|
      row.each_with_index do |cell, x|
        elements_to_move << [x, y, cell] if cell
      end
    end
    
    # Move a few random elements to empty spaces
    elements_to_move.sample([elements_to_move.length / 4, 1].max).each do |x, y, element|
      empty_space = find_random_empty_space(x, y)
      if empty_space
        new_x, new_y = empty_space
        board[y][x] = nil
        board[new_y][new_x] = element
      end
    end
  end
end 