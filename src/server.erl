%% This module provides the protocol that to interact with a chat service.
%%
%% The interface is design to be synchronous: it waits for the reply of the
%% system.
%%
%% This module defines the public API that is supposed to be used for
%% experiments. The semantics of the API here should remain unchanged.
-module(server).

-export([register_user/2, log_in/2, log_out/2, join_channel/3, join_channel/2, send_message/3,
         get_channel_history/2, create_channel/2]).

%%
%% Server API
%%

% Register a new user.
%
% Returns a pid that should be used for subsequent requests by this client.
-spec register_user(pid(), string()) -> {pid(), user_registered}.
register_user(ServerPid, UserName) ->
    ServerPid ! {self(), register_user, UserName},
    receive
        {ResponsePid, user_registered} ->
            {ResponsePid, user_registered}
    end.

% Log in.
% For simplicity, we do not request a password: authorization and security are
% not regarded in any way.
%
% Returns a pid that should be used for subsequent requests by this client.
-spec log_in(pid(), string()) -> {pid(), logged_in}.
log_in(ServerPid, UserName) ->
    ServerPid ! {self(), log_in, UserName},
    receive
        {ResponsePid, logged_in} ->
            {ResponsePid, logged_in}
    end.

% Log out.
-spec log_out(pid(), string()) -> logged_out.
log_out(ServerPid, UserName) ->
    ServerPid ! {self(), log_out, UserName},
    receive
        {_ResponsePid, logged_out} ->
            logged_out
    end.

% Join a channel. Admin mode on master server
-spec join_channel(pid(), string(), string()) -> channel_joined.
join_channel(ServerPid, UserName, ChannelName) ->
    ServerPid ! {self(), join_channel, UserName, ChannelName},
    receive
        {_ResponsePid, channel_joined} ->
            channel_joined
    end.

% Join a channel. Client mode
-spec join_channel(pid(), string()) -> channel_joined.
join_channel(SocketPid, ChannelName) ->
    SocketPid ! {self(), join_channel, ChannelName},
    receive
        {_ResponsePid, channel_joined} ->
            channel_joined
    end.

% Send a message to a channel.
-spec send_message(pid(), string(), string()) -> message_sent.
send_message(ServerPid, ChannelName, MessageText) ->
    ServerPid ! {self(), send_message, ChannelName, MessageText, os:system_time()},
    receive
        {_ResponsePid, message_sent} ->
            message_sent
    end.

% Get channel's history.
% Each message has the form:
%   {message, UserName, ChannelName, MessageText, SendTime}
-spec get_channel_history(pid(), string()) -> list({message, string(), string(), string(), integer()}).
get_channel_history(ServerPid, ChannelName) ->
    ServerPid ! {self(), get_channel_history, ChannelName},
    receive
        {_ResponsePid, channel_history, Messages} ->
            Messages
    end.

% Create a new channel
-spec create_channel(pid(), string()) -> channel_created.
create_channel(ServerPid, ChannelName) ->
	ServerPid ! {self(), create_channel, ChannelName},
	receive
		{_ResponsePid, channel_created} ->
			channel_created
	end.

%%
%% Client API
%%

% A client can receive the following message:
%   {ServerPid, new_message, {message, UserName, ChannelName, MessageText, SendTime}}
