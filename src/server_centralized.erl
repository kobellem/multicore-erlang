%% This is a simple implementation of the project, using one centralized server.
%%
%% It will create one "server" actor that contains all internal state (users and
%% their subscriptions, channels and their messages, and logged in users).
%%
%% This implementation is provided with unit tests. However, these tests are
%% neither complete nor implementation independent. Thus, be careful when
%% reusing them.
-module(server_centralized).

-include_lib("eunit/include/eunit.hrl").

-export([initialize/0, initialize_with/3, server_actor/3, typical_session_1/1,
		 typical_session_2/1]).

%%
%% Additional API Functions
%%

% Start server.
initialize() ->
	% Create a new main channel
	Users = sets:new(),
	LoggedIn = dict:new(),
	MainChannelPid = spawn_link(channel, channel_actor, [Users, LoggedIn, []]),
	Channels = dict:store(main, MainChannelPid, dict:new()),
	initialize_with(dict:new(), LoggedIn, Channels).

% Start server with an initial state.
% Useful for benchmarking.
initialize_with(Users, LoggedIn, Channels) ->
	ServerPid = spawn_link(?MODULE, server_actor, [Users, LoggedIn, Channels]),
	catch unregister(server_actor),
	register(server_actor, ServerPid),
	ServerPid.

% The server actor works like a small database and encapsulates all state of
% this simple implementation.
%
% * Users is a dictionary of user names to tuples of the form:
%	 {user, Name, Subscriptions}
%   where Subscriptions is a set of channels that the user joined.
% * LoggedIn is a dictionary of the names of logged in users and their pid.
% * Channels is a dictionary of channel names and their pid's:
%	 {channel, Name, Pid}
%   where Messages is a list of messages, of the form:
%	 {message, UserName, ChannelName, MessageText, SendTime}
server_actor(Users, LoggedIn, Channels) ->
	receive
		{Sender, register_user, UserName} ->
			% Join user in main channel
			ChannelPid = dict:fetch(main, Channels), % assumes main channel exists
			ChannelPid ! {Sender, join_channel, UserName},
			Subscriptions = sets:new(),
			NewUsers = dict:store(UserName, {user, UserName, sets:add_element(main, Subscriptions)}, Users),
			% Send confirmation to client
			Sender ! {self(), user_registered},
			server_actor(NewUsers, LoggedIn, Channels);

		{Sender, log_in, UserName} ->
			NewLoggedIn = dict:store(UserName, Sender, LoggedIn),
			% Send logged in signal to all subscribed channels
			{_, _, Subscriptions} = dict:fetch(UserName, Users), % assumes user exists
			SubscriptionList = sets:to_list(Subscriptions),
			Login = fun(ChannelName) ->
				ChannelPid = dict:fetch(ChannelName, Channels), % assumes channel exists
				ChannelPid ! {Sender, log_in, UserName}
			end,
			lists:foreach(Login, SubscriptionList),
			server_actor(Users, NewLoggedIn, Channels);

		{Sender, log_out, UserName} ->
			NewLoggedIn = dict:erase(UserName, LoggedIn),
			% Send logged out signal to all subscribed channels
			{_, _, Subscriptions} = dict:fetch(UserName, Users), % assumes user exists
			SubscriptionList = sets:to_list(Subscriptions),
			Logout = fun(ChannelName) ->
				ChannelPid = dict:fetch(ChannelName, Channels), % assumes channel exists
				ChannelPid ! {Sender, log_out, UserName}
			end,
			lists:foreach(Logout, SubscriptionList),
			server_actor(Users, NewLoggedIn, Channels);

		{Sender, join_channel, UserName, ChannelName} ->
			User = dict:fetch(UserName, Users), % assumes user exists
			NewUser = join_channel(User, ChannelName),
			NewUsers = dict:store(UserName, NewUser, Users),
			% Send join user signal to channel
			ChannelPid = dict:fetch(ChannelName, Channels), % assumes channel exists
			ChannelPid ! {Sender, join_channel, UserName},
			server_actor(NewUsers, LoggedIn, Channels);

		{Sender, send_message, UserName, ChannelName, MessageText, SendTime} ->
			% send message to channel
			ChannelPid = dict:fetch(ChannelName, Channels),
			ChannelPid ! {Sender, send_message, UserName, MessageText, SendTime},
			server_actor(Users, LoggedIn, Channels);

		{Sender, get_channel_history, ChannelName} ->
			ChannelPid = dict:fetch(ChannelName, Channels),
			ChannelPid ! {Sender, get_channel_history},
			server_actor(Users, LoggedIn, Channels);

		{Sender, create_channel, ChannelName} ->
			ChannelPid = 	spawn_link(channel, channel_actor, [sets:new(), dict:new(), []]),
			NewChannels = dict:store(ChannelName, ChannelPid, Channels),
			% Send confirmation to client
			Sender ! {self(), channel_created},
			server_actor(Users, LoggedIn, NewChannels)
	end.

%%
%% Internal Functions
%%

% Modify `User` to join `ChannelName`.
join_channel({user, Name, Subscriptions}, ChannelName) ->
	{user, Name, sets:add_element(ChannelName, Subscriptions)}.

%%
%% Tests
%%
% These tests are for this specific implementation. They are a partial
% definition of the semantics of the provided interface but also make certain
% assumptions of the implementation. You can re-use them, but you might need to
% modify them.

initialize_test() ->
	catch unregister(server_actor),
	initialize().

register_user_test() ->
	initialize_test(),
	?assertMatch({_, user_registered}, server:register_user(server_actor, "A")),
	?assertMatch({_, user_registered}, server:register_user(server_actor, "B")),
	?assertMatch({_, user_registered}, server:register_user(server_actor, "C")),
	?assertMatch({_, user_registered}, server:register_user(server_actor, "D")),
	["A", "B", "C", "D"].

log_in_test() ->
	[UserName1, UserName2 | _] = register_user_test(),
	?assertMatch({_Server1, logged_in}, server:log_in(server_actor, UserName1)),
	?assertMatch({_Server2, logged_in}, server:log_in(server_actor, UserName2)).
	% Note: returned pids _Server1 and _Server2 do not necessarily need to be
	% the same.

log_out_test() ->
	[UserName1, UserName2 | _] = register_user_test(),
	{Server1, logged_in} = server:log_in(server_actor, UserName1),
	{Server2, logged_in} = server:log_in(server_actor, UserName2),
	?assertMatch(logged_out, server:log_out(Server1, UserName1)),
	?assertMatch(logged_out, server:log_out(Server2, UserName2)).

join_channel_test() ->
	[UserName1 | _] = register_user_test(),
	{Server1, logged_in} = server:log_in(server_actor, UserName1),
	?assertMatch(channel_joined,
		server:join_channel(Server1, UserName1, channel1)),
	?assertMatch(channel_joined,
		server:join_channel(Server1, UserName1, channel2)),
	{UserName1, Server1, channel1, channel2}.

send_message_test() ->
	{UserName1, Server1, Channel1, _Channel2} = join_channel_test(),
	?assertMatch(message_sent,
		server:send_message(Server1, UserName1, Channel1, "Hello!")),
	?assertMatch(message_sent,
		server:send_message(Server1, UserName1, Channel1, "How are you?")).

channel_history_test() ->
	% Create users, log in, join channels.
	[UserName1, UserName2 | _] = register_user_test(),
	{Server1, logged_in} = server:log_in(server_actor, UserName1),
	{Server2, logged_in} = server:log_in(server_actor, UserName2),
	Channel1 = channel1,
	server:join_channel(Server1, UserName1, Channel1),
	server:join_channel(Server2, UserName2, Channel1),

	% Send some messages
	server:send_message(Server1, UserName1, Channel1, "Hello!"),
	server:send_message(Server2, UserName2, Channel1, "Hi!"),
	server:send_message(Server1, UserName1, Channel1, "How are you?"),

	% Check history
	[{message, UserName1, Channel1, "Hello!", Time1},
	 {message, UserName2, Channel1, "Hi!", Time2},
	 {message, UserName1, Channel1, "How are you?", Time3}] =
		server:get_channel_history(Server1, Channel1),
	?assert(Time1 =< Time2),
	?assert(Time2 =< Time3).

typical_session_test() ->
	initialize_test(),
	Session1 = spawn_link(?MODULE, typical_session_1, [self()]),
	Session2 = spawn_link(?MODULE, typical_session_2, [self()]),
	receive
		{Session1, ok} ->
			receive
				{Session2, ok} ->
					done
			end
	end.

typical_session_1(TesterPid) ->
	{_, user_registered} = server:register_user(server_actor, "Jennifer"),
	{Server, logged_in} = server:log_in(server_actor, "Jennifer"),
	channel_joined = server:join_channel(Server, "Jennifer", "multicore"),
	message_sent = server:send_message(Server, "Jennifer", "multicore", "Hello!"),
	% Wait for reply
	Time2 = receive
		{_, new_message, Message} ->
			?assertMatch({message, "Janwillem", "multicore", "Hi!", _}, Message),
			{message, _, _, _, Time} = Message,
			Time
	end,
	% Respond
	message_sent = server:send_message(Server, "Jennifer", "multicore", "How are you?"),

	% Check history
	[{message, "Jennifer",  "multicore", "Hello!",	   Time1},
	 {message, "Janwillem", "multicore", "Hi!",		  Time2},
	 {message, "Jennifer",  "multicore", "How are you?", Time3}] =
		server:get_channel_history(Server, "multicore"),
	?assert(Time1 =< Time2),
	?assert(Time2 =< Time3),

	TesterPid ! {self(), ok}.

typical_session_2(TesterPid) ->
	{_, user_registered} = server:register_user(server_actor, "Janwillem"),
	{Server, logged_in} = server:log_in(server_actor, "Janwillem"),
	channel_joined = server:join_channel(Server, "Janwillem", "multicore"),
	% Wait for first message
	Time1 = receive
		{_, new_message, Message1} ->
			?assertMatch({message, "Jennifer", "multicore", "Hello!", _}, Message1),
			{message, _, _, _, Time} = Message1,
			Time
	end,
	% Reply
	message_sent = server:send_message(Server, "Janwillem", "multicore", "Hi!"),
	% Wait for response
	Time3 = receive
		{_, new_message, Message3} ->
			?assertMatch({message, "Jennifer", "multicore", "How are you?", _}, Message3),
			{message, _, _, _, Time_} = Message3,
			Time_
	end,

	% Check history
	[{message, "Jennifer",  "multicore", "Hello!",	   Time1},
	 {message, "Janwillem", "multicore", "Hi!",		  Time2},
	 {message, "Jennifer",  "multicore", "How are you?", Time3}] =
		server:get_channel_history(Server, "multicore"),
	?assert(Time1 =< Time2),
	?assert(Time2 =< Time3),

	TesterPid ! {self(), ok}.
