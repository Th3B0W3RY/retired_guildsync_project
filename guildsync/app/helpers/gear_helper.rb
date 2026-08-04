module GearHelper
  def status_badge_class_helper(status)
    case status
    when 'up_to_date'
      'bg-green-100 text-green-800'
    when 'outdated'
      'bg-yellow-100 text-yellow-800'
    when 'missing'
      'bg-red-100 text-red-800'
    else
      'bg-gray-100 text-gray-800'
    end
  end
end

