class Profile
  # TODO: hook into your own profile pictures here
  def primary_photo(username)
    # stock photo...fallback for users who don't have a profile picture
    "/profile_default.jpg"
  end
end
