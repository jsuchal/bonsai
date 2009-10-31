module PageHelper
  def image_boolean(value, title = nil)
    return value ? image_tag("icons/accept.png", :alt => 'Yes', :title => title) : image_tag("icons/delete.png", :alt => 'No', :title => title);
  end

  def rss_url page, user
    token_string = user.token.nil? ? '' : "&amp;token=#{user.token}"
    page.get_path + '?rss' + token_string
  end

  def link_to_page page
    link_to page.title, page.get_path
  end

def find_level node
    count = 0
    jupik = node

    while (not(jupik.parent.nil?) and jupik.level.nil?)
      count += 1
      jupik=jupik.parent
    end

    if jupik.level.nil?
      return count
    else
      return count + jupik.level
    end
  end

  def find_level_depth nodes
    for node in nodes
      if node.parent_id.nil?
          node.level=0
        end
          node.level=find_level(node)
      end
    return nodes
  end
end
