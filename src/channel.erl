-module(channel).

-export([initialize_with/2, channel_actor/3]).

% Start new channel
initialize_with(Users, LoggedIn) ->
	ChannelPid = spawn_link(?MODULE, channel_actor, [Users, LoggedIn, dict:new()]),
	catch unregister(channel_actor),
	ChannelPid.

channel_actor(Users, LoggedIn, Messages) ->
	receive
		{Sender, join_channel, UserName} ->
			NewUsers = sets:add_element(UserName, Users),
			Sender ! {self(), channel_joined},
			channel_actor(NewUsers, LoggedIn, Messages);

		{Sender, log_in, UserName} ->
			NewLoggedIn = dict:store(UserName, Sender, LoggedIn),
			% Sender ! {self(), logged_in},
			channel_actor(Users, NewLoggedIn, Messages);

		{Sender, log_out, UserName} ->
			NewLoggedIn = dict:erase(UserName, LoggedIn),
			% Sender ! {self(), logged_out},
			channel_actor(Users, NewLoggedIn, Messages);

		{Sender, send_message, UserName, MessageText, SendTime} ->
			Message = {message, UserName, MessageText, SendTime},
			NewMessages = lists:append([Message], Messages),
			% broadcast to all logged in users
			dict:map(fun(_, UserPid) ->
				UserPid ! {self(), new_message, Message}
			end, LoggedIn),
			Sender ! {self(), message_sent},
			channel_actor(Users, LoggedIn, NewMessages);

		{Sender, get_channel_history} ->
			Sender ! {self(), channel_history, Messages},
			channel_actor(Users, LoggedIn, Messages)
	end.
