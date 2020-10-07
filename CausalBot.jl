#!/usr/local/bin/julia

using Twitter, OAuth, CSV, Dates, DataFrames, Random, StatsBase

# the functions

"""
   Spoof a re-tweet and print to stdout. For testing.
"""
function fake_retweet(tweet)
  println(tweet.text * " - " * tweet.user["screen_name"])
end

"""
   Send out a real re-tweet
"""
function real_retweet(tweet)
  post_status_retweet_id(tweet.id_str)
end


"""
   Get all prior re-tweets of the bot, by tweet id_str.
"""
function get_my_ids(un;fn = "pasttweets.csv")
  dt = DataFrame(CSV.File(fn)); # stored
  mytimeline = get_user_timeline(screen_name = un, count=100); # new
  rtids = [m.retweeted_status["id_str"] for m in mytimeline if !isnothing(m.retweeted_status)]
  myids = unique(vcat(rtids, [m.id_str for m in mytimeline], [string(d) for d in dt.myids]))
  myids
end

"""
   Filter out tweets that will be skipped
"""
function hard_filter_tweets(collection; bans=[])
  idx = []
  for (i,tweet) in enumerate(collection["statuses"])
    #
    Iretweeted = any(tweet.id_str .== myids) ? true : false
    newtweet = (isnothing(tweet.retweeted_status) && (tweet.text[1:2] != "RT")) # revisit
    isbanned = any(tweet.user["screen_name"] .== bans)
    idx = (Iretweeted | !newtweet | isbanned) ? idx : vcat(idx,i)
  end
  idx
end

"""
   Sample from eligible tweets
"""
function soft_filter_tweets(collection, okindex; maxtweets=5, vips=[], vivips=[], lvips=[])
  length(okindex)==0 && return okindex
  psamp = rand(length(okindex))
  for (i, tweet) in enumerate(collection["statuses"][okindex])
    isreply = (tweet.in_reply_to_screen_name == "")
    isvip = any(tweet.user["screen_name"] .== vips)
    isvivip = any(tweet.user["screen_name"] .== vivips)
    islvip = any(tweet.user["screen_name"] .== lvips)
    psamp[i] = min(1.0, max(0.0, 0.3 + isvip*0.3 + isvivip*0.7 - islvip*0.2 - isreply*0.2))
  end
  # from StatsBase
  unique(sample(okindex, fweights(psamp), maxtweets))
end


"""
   Tweet
"""
function retweet!(myids,collection,yesindex;maxtweets=5, fake=false)
  length(okindex)==0 && return okindex
  order = rand(yesindex, length(yesindex))
  for tweet in collection["statuses"][order]
    fake ? fake_retweet(tweet) : real_retweet(tweet)
    myids = fake ? myids : vcat(myids, tweet.id_str)
  end
end 

"""
   Dev helper function
"""
function rolltweets(uid,collection)
    for tweet in collection["statuses"]
      uid == tweet.user["id_str"] ? print(tweet.text) : true
    end
end


"""
   Dev helper function
"""
function collect_mentions(id_str)
  for tweet in collection["statuses"]
    break
  end
end



############################################ prelims #####################################
  hd = homedir();
  cd(hd*"/repo/CausalBot")

############################################ authorization ###############################
  include("private_keys.txt"); # keys + vips list + banned user list
  auth_dictionary = twitterauth(ak, ask, at, ats);

################################## hashtags to retweet ###################################
  hashlist = ["#CausalTwitter", "#causal", "#causalinference", "#causalinf"];

############################################ misc ########################################
  #checktweets = get_search_tweets(q = hashlist[1], count = 1000)

  #rolltweets(special, checktweets)


################################## all of my tweets, retweets ############################
  myids = get_my_ids(un);


################################## select recent tweets ##################################
  causaltweets = get_search_tweets(q = hashlist[1], count = 500)
  okindex = hard_filter_tweets(causaltweets; bans=bans);
  yesindex = soft_filter_tweets(causaltweets, okindex; maxtweets=5, vips=vips, vivips=vivips, lvips=lvips);
  
  # if desperate, pull randomly from another related hashtag
  if length(yesindex)==0
    causaltweets = get_search_tweets(q = rand(hashlist[2:end]), count = 500)
    okindex = hard_filter_tweets(causaltweets; bans=bans);
    yesindex = soft_filter_tweets(causaltweets, okindex; maxtweets=2, vips=vips, vivips=vivips, lvips=lvips);
  end
  
################################### retweet, if any ######################################
  retweet!(myids, causaltweets, yesindex, fake=false)

################################## remember old retweets #################################
  CSV.write("pasttweets.csv", DataFrame(myids=myids));

println(Dates.now())
