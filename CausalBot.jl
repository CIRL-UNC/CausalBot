#!/usr/local/bin/julia

using Twitter, CSV, Dates, DataFrames, StatsBase, JSON
import Twitter.get_oauth, Twitter.Users

# the functions

"""
   Spoof a re-tweet and print to stdout. For testing.
"""
function fake_retweet!(myids, tweet)
  println(tweet.text * " - " * tweet.user["screen_name"])
  myids = myids
end

"""
   Send out a real re-tweet, catching some old RT that were missed
"""
function real_retweet!(myids, tweet)
  newid = tweet.id_str
  try
    post_status_retweet_id(newid)
  catch err
     # unclear why this is needed, but error happens if I had already retweeted
     # and somehow didn't catch it through other means
     # this will just assume a 403 error means I should add to the list of 
     # retweets
     myids  = err.response.status == 403 ? vcat(newid, myids) : myids
  end
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
   Handle non-ascii text graciously when indexing text of a Tweet
   s = "¿Según"
   first_two_chars(s)
   # s[1:2] # does not work
"""
function first_two_chars(str)
  str[nextind(str, 0):nextind(str, 1)]
end

"""
   Filter out tweets that will be skipped
"""
function hard_filter_tweets(collection; bans=[], allowretweets=true)
  idx = []
  for (i,tweet) in enumerate(collection["statuses"])
    #
    Iretweeted = any(tweet.id_str .== myids) ? true : false
    newtweet = allowretweets || (isnothing(tweet.retweeted_status) && (first_two_chars(tweet.text) != "RT")) 
    isbanned = any(tweet.user["screen_name"] .== bans)
    idx = (Iretweeted | !newtweet | isbanned) ? idx : vcat(idx,i)
  end
  idx
end

"""
   Sample from eligible tweets, sampling based on VIP status
   NOTE: VIP status is based on Twitter users currently being amplified
     and NOT necessarily popular users. VIP lists are private but can be 
     obtained for auditing purposes by a DM to @PronouncedKeil
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
    fake ? fake_retweet!(myids, tweet) : real_retweet!(myids, tweet)
    myids = fake ? myids : vcat(tweet.id_str, myids)
  end
end 

"""
   Dev helper function: collect all tweets from a user in the queue
"""
function rolltweets(uid,collection)
    for tweet in collection["statuses"]
      uid == tweet.user["id_str"] ? print(tweet.text) : true
    end
end

"""
   Dev helper function: in progress
"""
function collect_mentions(id_str, collection)
  for tweet in collection["statuses"]
    break
  end
end


"""
   Dev helper function: get all usernames from a twitter list
   This is a kludge to replace Twitter.get_lists_members, which misreads the json data
"""
function myget_lists_members(;kwargs...)
   options = Dict{String, Any}()
   for arg in kwargs
       options[string(arg[1])] = string(arg[2])
   end
   cur_alloc = reconnect("lists/members.json") # start reconnect loop
   r = get_oauth("https://api.twitter.com/1.1/lists/members.json", options)
   if r.status == 200
       success = JSON.parse(String(r.body))
       return(Users(success["users"]))
   else
       error("Twitter API returned $(r.status) status")
   end
end


"""
   Dev helper function: get all usernames from a twitter list
"""
function extract_list_uns(list_id)
    subs = myget_lists_members(list_id=list_id, count=10000, skip_status=true)
    [s.screen_name for s in subs]
end



############################################ prelims #####################################
  hd = homedir();
  cd(hd*"/repo/CausalBot")

############################################ authorization ###############################
  include("private_keys.txt"); # keys + speciallist + vips/vivips/lvips/bans lists
  auth_dictionary = twitterauth(ak, ask, at, ats);

################################## hashtags to retweet ###################################
  #hashlist = ["#CausalTwitter", "#causal", "#causalinference", "#causalinf"]; # too many links to misspelled "casual" tags
  hashlist = ["#CausalTwitter", "#causalinference", "#causalml", "causality"];

############################################ misc ########################################
  #checktweets = get_search_tweets(q = hashlist[1], count = 1000)
  #rolltweets(special, checktweets)
  vips = sort(unique(vcat(vips, extract_list_uns(speciallist))));

################################## all of my tweets, retweets ############################
  myids = get_my_ids(un);


################################## select recent tweets ##################################
  causaltweets = get_search_tweets(q = hashlist[1], count = 10000)
  okindex = hard_filter_tweets(causaltweets; bans=bans, allowretweets=false);
  yesindex = soft_filter_tweets(causaltweets, okindex; maxtweets=5, vips=vips, vivips=vivips, lvips=lvips);
  
  # if desperate, pull randomly from another related hashtag on occasion
  if (length(yesindex)==0 && rand()>0.7)
    causaltweets = get_search_tweets(q = rand(hashlist[2:end]), count = 200)
    okindex = hard_filter_tweets(causaltweets; bans=bans, allowretweets=false);
    yesindex = soft_filter_tweets(causaltweets, okindex; maxtweets=1, vips=vips, vivips=vivips, lvips=lvips);
  end
  
################################### retweet, if any ######################################
  if length(yesindex)>0
    retweet!(myids, causaltweets, yesindex, fake=true)
    CSV.write("pasttweets.csv", DataFrame(myids=myids));
  end


println(Dates.now())
