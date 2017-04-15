%% This is a simple implementation of the project, using one centralized server.
%%
%% It will create one "server" actor that contains all internal state (users and
%% their subscriptions, channels and their messages, and logged in users).
%%
%% This implementation is provided with unit tests. However, these tests are
%% neither complete nor implementation independent. Thus, be careful when
%% reusing them.
-module(server_centralized).

-export([initialize/0, initialize_with/3, server_actor/3]).

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
%	 TODO remove assumptions, they can only crash the program
server_actor(Users, LoggedIn, Channels) ->
	receive
		{Sender, register_user, UserName} ->
			% Join user in main channel
			ChannelPid = dict:fetch(main, Channels), % assumes main channel exists
			ChannelPid ! {self(), join_channel, UserName},
			receive
				{_MainChannelPid, channel_joined} ->
					ok
			end,
			Subscriptions = sets:new(),
			NewUsers = dict:store(UserName, {user, UserName, sets:add_element(main, Subscriptions)}, Users),
			% Send confirmation to client
			Sender ! {self(), user_registered},
			server_actor(NewUsers, LoggedIn, Channels);

		{Sender, log_in, UserName} ->
			NewLoggedIn = dict:store(UserName, Sender, LoggedIn),
			% Send logged in signal to all subscribed channels
			{_, _, Subscriptions} = dict:fetch(UserName, Users), % assumes user exists
			UserChannels = filter_channels(Subscriptions, Channels),
			spawn_link(socket, initialize, [self(), Sender, UserName, UserChannels]),
			server_actor(Users, NewLoggedIn, Channels);

		{Sender, log_out, UserName} ->
			NewLoggedIn = dict:erase(UserName, LoggedIn),
			Sender ! {self(), logged_out},
			server_actor(Users, NewLoggedIn, Channels);

		{Sender, join_channel, UserName, ChannelName} ->
			User = dict:fetch(UserName, Users), % assumes user exists
			NewUser = join_channel(User, ChannelName),
			NewUsers = dict:store(UserName, NewUser, Users),
			% Send join user signal to channel
			ChannelPid = dict:fetch(ChannelName, Channels), % assumes channel exists
			ChannelPid ! {Sender, join_channel, UserName},
			server_actor(NewUsers, LoggedIn, Channels);

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

% Get a filtered channels dict based on user subscriptions
filter_channels(Subscriptions, Channels) ->
	SubscriptionList = sets:to_list(Subscriptions),
	Filter = fun(ChannelName, _) ->
		lists:member(ChannelName, SubscriptionList)
	end,
	dict:filter(Filter, Channels).
