-module(socket).

-export([initialize/4]).

% Data:
% MainServerPid = int
% UserName = string
% Channels = dict(string, int)

initialize(MainServerPid, Sender, UserName, Channels) ->
	Login = fun(_, ChannelPid) ->
		ChannelPid ! {Sender, log_in, UserName}
	end,
	_ = dict:map(Login, Channels),
	% Send pid to client for further communication
	Sender ! {self(), logged_in},
	% Start the socket actor for receiving messages
	socket_actor(MainServerPid, UserName, Channels).

socket_actor(MainServerPid, UserName, Channels) ->
	receive
		{Sender, log_out, _} ->
			% Log out in all channels
			Logout = fun(_, ChannelPid) ->
				ChannelPid ! {Sender, log_out, UserName}
			end,
			_ = dict:map(Logout, Channels),
			% Log out main server
			% This actor shuts down afterwards
			MainServerPid ! {Sender, log_out, UserName};

		{Sender, join_channel, ChannelName} ->
			% Handled by main server
			% Wait for response to add ChannelPid to Channels
			MainServerPid ! {self(), join_channel, UserName, ChannelName},
			receive
				{ChannelPid, channel_joined} ->
					NewChannels = dict:store(ChannelName, ChannelPid, Channels),
					% Send confirmation to client
					Sender ! {ChannelPid, channel_joined},
					socket_actor(MainServerPid, UserName, NewChannels)
			end;

		{Sender, send_message, ChannelName, MessageText, SendTime} ->
			ChannelPid = dict:fetch(ChannelName, Channels),
			ChannelPid ! {Sender, send_message, UserName, MessageText, SendTime},
			socket_actor(MainServerPid, UserName, Channels);

		{Sender, get_channel_history, ChannelName} ->
			ChannelPid = dict:fetch(ChannelName, Channels),
			ChannelPid ! {Sender, get_channel_history},
			socket_actor(MainServerPid, UserName, Channels);

		{Sender, create_channel, ChannelName} ->
			% Handled by main server
			MainServerPid ! {Sender, create_channel, ChannelName},
			socket_actor(MainServerPid, UserName, Channels)
	end.
