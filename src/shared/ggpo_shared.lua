--!strict
local Queue = require(script.Parent.util.queue)

export type TimeMS = number

-- helpers
local function now() : TimeMS
    return DateTime.now().UnixTimestampMillis
end

local function Log(s, ...)
    return print(s:format(...))
end




-- CONSTANTS
local serverHandle = 99999999999
-- negative frames used for synchronizing start times
local frameInit = -10
local frameStart = 0
local frameNull = -999999999999
local frameMax = 9999999999999
local frameMin = frameNull+1 -- just so we can distinguish between null and min


-- TYPES
export type Frame = number
export type GGPOPlayerHandle = number

export type GameConfig = {
    numPlayers: number,
    inputDelay: number
}

export type GameInput<I> = {
    -- the destination frame of this input
    frame: Frame,

    -- set to whatever type best represents your game input. Keep this object small! Maybe use a buffer! https://devforum.roblox.com/t/introducing-luau-buffer-type-beta/2724894
    -- nil represents no input? (i.e. AddLocalInput was never called)
    input: I?
}
export type FrameInputMap<I> = {[Frame] : GameInput<I>}

function FrameInputMap_lastFrame<I>(msg : FrameInputMap<I>) : Frame
    if #msg == 0 then
        return frameNull
    end

    local lastFrame = frameMin
    for frame, input in pairs(msg) do
        if frame > lastFrame then
            lastFrame = frame
        end
    end
    return lastFrame
end

function FrameInputMap_firstFrame<I>(msg : FrameInputMap<I>) : Frame
    if #msg == 0 then
        return frameNull
    end

    local firstFrame = frameMax
    for frame, input in pairs(msg) do
        if frame < firstFrame then
            firstFrame = frame
        end
    end
    return firstFrame
end

export type PlayerFrameInputMap<I> = {[GGPOPlayerHandle] : FrameInputMap<I>}

function PlayerFrameInputMap_addInputs<I>(a : PlayerFrameInputMap<I>, b : PlayerFrameInputMap<I>)
    for player, frameData in pairs(b) do
        for frame, input in pairs(frameData) do
            -- TODO assert inputs are equal if present in a
            --if table.contains(a, player) and table.contains(a[player][frame]) and a[player][frame] ~= a[player][frame] then 
            a[player][frame] = input
        end
end

-- GGPOEvent types
export type GGPOEvent_synchronized = {
    player: GGPOPlayerHandle,
}
export type GGPOEvent_Input<I> = PlayerFrameInputMap<I>
export type GGPOEvent_interrupted = nil
export type GGPOEvent_resumed = nil
-- can we also embed this in the input, perhaps as a serverHandle input
export type GGPOEvent_disconnected = {
    player: GGPOPlayerHandle,
}
export type GGPOEvent<I> = GGPOEvent_synchronized | GGPOEvent_Input<I> | GGPOEvent_interrupted | GGPOEvent_resumed | GGPOEvent_disconnected
  


export type UDPMsg_Type = "Ping" | "Pong" | "InputAck" | "Input" | "QualityReport" 

-- TODO get rid of these underscores
-- UDPMsg types
-- these replace sync packets which are not needed for Roblox
export type UDPPeerMsg_Ping = { t: "Ping", time: TimeMS }
export type UDPPeerMsg_Pong = { t: "Pong", time: TimeMS }
export type UDPPeerMsg_InputAck = { t: "InputAck", frame : Frame }


export type QualityReport = { 
    frame_advantage : number, 
}

export type UDPMsg_QualityReport = {
    t: "QualityReport", 
    peer : QualityReport,
    player: {[GGPOPlayerHandle] : QualityReport},
    time : TimeMS,
}

export type UDPMsg_Input<I> = {
    t : "Input",
    frame : Frame, -- this should match the frame in input if the peer is also a player
    ack_frame : Frame,
    inputs : PlayerFrameInputMap<I>
}


export type UDPMsg_Contents<I> = 
    UDPPeerMsg_Ping
    | UDPPeerMsg_Pong
    | UDPPeerMsg_InputAck 
    | UDPMsg_QualityReport 
    | UDPMsg_Input<I> 
    | UDPMsg_QualityReport

export type UDPMsg<I> = {
    m : UDPMsg_Contents<I>,
    seq : number,
}

function UDPMsg_Size<I>(UDPMsg : UDPMsg<I>) : number
    return 0
end

export type UDPEndpoint<I> = {
    send: (UDPMsg<I>) -> (),
    subscribe: ((UDPMsg<I>)->()) -> (),
}

local uselessUDPEndpoint : UDPEndpoint<any> = {
    send = function(msg) end,
    subscribe = function(cb) end
}

export type PlayerProxyInfo<I> = {
    peer: GGPOPlayerHandle,
    -- which players are represented by this proxy
    -- in a fully connected P2P case this will be empty
    -- in when connecting to a routing server, this will be all players 
    proxy: {[number]: GGPOPlayerHandle},
    endpoint: UDPEndpoint<I>,

    -- TODO figure out best time to transmit this data? maybe a reliable explicit game start packet? or just transmit as frame 0 data? it's weird cuz you can't really forward simulate if you're stuck on frame 0 waiting for data, but maybe just wait is OK, or maybe use first 10 frames to sync and adjust rift etc
    -- use this to pass in deterministic per-player capabilities
    --data: G,
}




export type GGPONetworkStats = {
    max_send_queue_len : number,
    ping : number,
    kbps_sent : number,
    local_frames_behind : number,
    remote_frames_behind : number,
}

export type GGPOCallbacks<T,I> = {
    SaveGameState: (frame: number) -> T,
    LoadGameState: (T, frame: number) -> (),
    AdvanceFrame: () -> (),
    OnEvent: (event: GGPOEvent<I>) -> (),
    DisconnectPlayer: (GGPOPlayerHandle) -> ()
}



export type Sync<I> = {
    inputMap : PlayerFrameInputMap<I>,
}

function Sync_new<I>() : Sync<I>
    local r = {
        inputMap = {},
    }
    return r
end


export type UDPProto_Player<I> = {
    -- alternatively, consider storing these values as a { [GGPOPlayerHandle] : number } table, but this would require sending per player stats rather than just max
    -- (according to peer) frame peer - frame player
    frame_advantage : number,
    pending_output : {[Frame] : GameInput<I>},
    last_received_input : GameInput<I>,

   --disconnect_event_sent : number,
   --disconnect_timeout : number;
   --disconnect_notify_start : number;
   --disconnect_notify_sent : number;
    --TimeSync                   _timesync;
    --RingBuffer<UdpProtocol::Event, 64>  _event_queue;
}

function UDPProto_Player_new() : UDPProto_Player<any>
    local r = {
        frame_advantage = 0,
        pending_output = {},
        last_received_input = { frame = frameNull, input = nil },
        
    }
    return r
end

local MAX_SEQ_DISTANCE = 8

-- udp_proto
-- manages synchronizing with a single peer
-- in particular, manages the following:
-- sending and acking input
-- synchronizing (initialization)
-- tracks ping for frame advantage computation
export type UDPProto<I> = {

    -- id
    player : GGPOPlayerHandle,
    endpoint : UDPEndpoint<I>,

    -- configuration
    sendLatency : number,
    msPerFrame: number,

    -- rift calculation
    lastReceivedFrame : Frame,
    round_trip_time : TimeMS,
    -- (according to peer) frame peer - frame self
    remote_frame_advantage : number,
    -- (according to self) frame self - frame peer
    local_frame_advantage : number,

    -- stats
    packets_sent : number,
    bytes_sent : number,
    kbps_sent: number,
    stats_start_time : TimeMS,
    
    -- logging
    last_sent_input : GameInput<I>,

    -- running state
    --last_quality_report_time : number,
    --last_network_stats_interval : number,
    --last_input_packet_recv_time : number, 

    -- packet counting
    next_send_seq : number,
    next_recv_seq : number,

    event_queue : Queue<GGPOEvent<I>>,

    playerData : {[GGPOPlayerHandle] : UDPProto_Player<I>},

    -- shutdown/keepalive timers
    --shutdown_timeout : number,
    --last_send_time : number,
    --last_recv_time : number,
}

local function UDPProto_lastSynchronizedFrame<I>(udpproto : UDPProto<I>) : Frame
    local lastFrame = frameMax
    for player, data in pairs(udpproto.playerData) do
        if data.last_received_input.frame < lastFrame then
            lastFrame = data.last_received_input.frame
        end
    end
    if lastFrame == frameMax then
        lastFrame = frameNull
    end
    return lastFrame
end

local function UDPProto_new<I>(player : PlayerProxyInfo<I>) : UDPProto<I>

    local playerData = {}
    playerData[player.peer] = UDPProto_Player_new()
    -- TODO if server, maybe add other peers here as well 

    local r = {
        -- TODO set
        player = 0,
        endpoint = uselessUDPEndpoint,

        -- TODO configure
        sendLatency = 0,
        msPerFrame = 50,

        lastReceivedFrame = frameNull,
        round_trip_time = 0,
        remote_frame_advantage = 0,
        local_frame_advantage = 0,

        packets_sent = 0,
        bytes_sent = 0,
        kbps_sent = 0,
        stats_start_time = 0,


        last_sent_input = { frame = frameNull, input = nil },


        next_send_seq = 0,
        next_recv_seq = 0,

        --last_send_time = 0,
        --last_recv_time = 0,

        event_queue = Queue.new(),

        playerData = playerData,

    }
    return r
end

function UDPProto_SendPeerInput<I>(udpproto : UDPProto<I>, input : GameInput<I>)
    --_timesync.advance_frame(input, _local_frame_advantage, _remote_frame_advantage);
    --_pending_output.push(input);
    udpproto.playerData[udpproto.player].pending_output[input.frame] = input
    UDPProto_SendPendingOutput(udpproto);
end


function UDPProto_SendPendingOutput<I>(udpproto : UDPProto<I>)
    local msg : { [GGPOPlayerHandle] : UDPPlayerMsg_Input<I> } = {}

    for player, data in pairs(udpproto.playerData) do
        msg[player] = data.pending_output
    end
   
   --msg->u.input.ack_frame = _last_received_input.frame;
   UDPProto_SendMsg(udpproto, msg)
end

function UDPProto_SendInputAck<I>(udpproto : UDPProto<I>)
    -- ack the minimum of all the last received inputs for now
    -- TODO ack the sequence number in the future, and the server needs to keep track of seq -> player -> frames sent
    -- or you could ack the exact players/frames too 
    local minFrame = frameNull
    for player, data in pairs(udpproto.playerData) do
        if data.last_received_input.frame < minFrame then
            minFrame = data.last_received_input.frame
        end
    end
    local msg = { frame = minFrame }
    UDPProto_SendMsg(udpproto, msg)
end

function UDPProto_GetEvent<I>(udpproto : UDPProto<I>) : GGPOEvent<I>?
    return udpproto.event_queue:dequeue()
end


function UDPProto_OnLoopPoll<I>(udpproto : UDPProto<I>)
   
    local now = now()
    local next_interval = 0

    -- sync requests (not needed)

    -- send pending output

    -- send qulaity report

    -- update nteworkstats
    --udpproto.UpdateNetworkStats()

    -- send keep alive (not needed)

    -- send disconnect notification (omit)
    -- determine self disconnect (omit)
end



function UDPProto_SendMsg<I>(udpproto : UDPProto<I>, msgc : UDPMsg_Contents<I>)
    local msg = {
        m = msgc,
        seq = udpproto.next_send_seq,
    }
    udpproto.next_send_seq += 1
    udpproto.packets_sent += 1
    udpproto.bytes_sent += UDPMsg_Size(msg)

    Log("SendMsg: %s", msg)
    --_last_send_time = Platform::GetCurrentTimeMS();
    udpproto.endpoint.send(msg)
end



local UDP_HEADER_SIZE = 0
local function UDPProto_UpdateNetworkStats<I>(udpproto : UDPProto<I>) 
   local now = now()
   
   if udpproto.stats_start_time == 0 then
      udpproto.stats_start_time = now
   end

   local total_bytes_sent = udpproto.bytes_sent + (UDP_HEADER_SIZE * udpproto.packets_sent)
   local seconds = (now - udpproto.stats_start_time) / 1000
   local bps = total_bytes_sent / seconds;
   local udp_overhead = (100.0 * (UDP_HEADER_SIZE * udpproto.packets_sent) / udpproto.bytes_sent)

   udpproto.kbps_sent = bps / 1024;

   Log("Network Stats -- Bandwidth: %.2f KBps   Packets Sent: %5d (%.2f pps)   KB Sent: %.2f    UDP Overhead: %.2f %%.\n",
       udpproto.kbps_sent,
       udpproto.packets_sent,
       udpproto.packets_sent * 1000 / (now - udpproto.stats_start_time),
       total_bytes_sent / 1024.0,
       udp_overhead)
end

local function UDPProto_QueueEvent<I>(udpproto : UDPProto<I>, evt : GGPOEvent<I>)
    Log("Queuing event: %s", evt);
    udpproto.event_queue:enqueue(evt)
end

local function UDPProto_OnInput<I>(udpproto : UDPProto<I>, msg :  UDPMsg_Input<I>) 

    udpproto.lastReceivedFrame = msg.frame

    local inputs = msg.inputs
    if #inputs == 0 then
        Log("UDPProto_OnInput: Received empty msg")
        return
    end

    local lastFrame
    for player, data in pairs(inputs) do
        
        -- for now, assume frames are contiguous
        lastFrame = FrameInputMap_lastFrame(data)

        
        if lastFrame ~= frameNull then
            udpproto.playerData[player].last_received_input = data[lastFrame]
        end
    end

    UDPProto_QueueEvent(udpproto, inputs)
end

local function UDPProto_OnInputAck<I>(udpproto : UDPProto<I>, msg : UDPPeerMsg_InputAck) 
    -- remember, we ack the min frame of all inputs we received for now
    for player, data in pairs(udpproto.playerData) do
        local start = FrameInputMap_firstFrame(data.pending_output)
        if start ~= frameNull and start <= msg.frame then
            for i = start, msg.frame, 1 do
                table.remove(data.pending_output, i)
            end
        end
    end
end


local function UDPProto_OnPing<I>(udpproto : UDPProto<I>, msg : UDPPeerMsg_Ping) 
    UDPProto_SendMsg(udpproto, { t = "Pong", time = msg.time })
end

local function UDPProto_OnPong<I>(udpproto : UDPProto<I>, msg : UDPPeerMsg_Pong) 
    -- TODO maybe rolling average this?
    udpproto.round_trip_time = now() - msg.time
end

local function UDPProto_OnQualityReport<I>(udpproto : UDPProto<I>, msg : UDPMsg_QualityReport) 
    udpproto.remote_frame_advantage = msg.peer.frame_advantage
    for player, data in pairs(msg.player) do
        udpproto.playerData[player].frame_advantage = data.frame_advantage
    end

    UDPProto_SendMsg(udpproto, { t = "Pong", time = msg.time })
end


function UDPProto_OnMsg<I>(udpproto : UDPProto<I>, msg : UDPMsg<I>) 

    --filter out out-of-order packets
    local skipped = msg.seq - udpproto.next_recv_seq
    if skipped > MAX_SEQ_DISTANCE then
        Log("Dropping out of order packet (seq: %d, last seq: %d)", msg.seq, udpproto.next_recv_seq)
        return
    end

    udpproto.next_recv_seq = msg.seq;
    Log("recv %s", msg)

    if msg.m.t == "Ping" then
        UDPProto_OnPing(udpproto, msg.m)
    elseif msg.m.t == "Pong" then
        UDPProto_OnPong(udpproto, msg.m)
    elseif msg.m.t == "InputAck" then
        UDPProto_OnInputAck(udpproto, msg.m)
    elseif msg.m.t == "Input" then
        UDPProto_OnInput(udpproto, msg.m)
    elseif msg.m.t == "QualityReport" then
        UDPProto_OnQualityReport(udpproto, msg.m)
    else
        Log("Unknown message type: %s", msg.m.t)
    end

    -- TODO resume if disconnected
    --_last_recv_time = Platform::GetCurrentTimeMS();
end

function UDPProto_GetNetworkStats(udpproto : UDPProto<I>) : GGPONetworkStats

    local maxQueueLength = 0
    for player, data in pairs(udpproto.playerData) do
        if #data.pending_output > maxQueueLength then
            maxQueueLength = #data.pending_output
        end
    end
    
    local s = {
        max_send_queue_len = maxQueueLength,
        ping = udpproto.round_trip_time,
        kbps_sent = udpproto.kbps_sent,
        local_frames_behind = udpproto.local_frame_advantage,
        remote_frames_behind = udpproto.remote_frame_advantage,
    }

    return s
end
    
function UDPProto_SetLocalFrameNumber(udpproto : UDPProto<I>, localFrame : number)

    local remoteFrame = udpproto.lastReceivedFrame + udpproto.round_trip_time / udpproto.msPerFrame / 2
    udpproto.local_frame_advantage = remoteFrame - localFrame
end
   
function UDPProto_RecommendFrameDelay(udpproto : UDPProto<I>) : number
    -- TODO
   --// XXX: require idle input should be a configuration parameter
   --return _timesync.recommend_frame_wait_duration(false);
   return 0
end







-- GGPO_Peer
local GGPO_Peer = {}

-- ggpo_get_network_stats
function GGPO_Peer.GetStats() : GGPONetworkStats 
    return nil
end

function GGPO_Peer.GetCurrentFrame() : number
    return 0
end

-- ggpo_synchronize_input
function GGPO_Peer.GetCurrentInput<I>() : {[GGPOPlayerHandle] : GameInput<I>} 
    return {}
end

-- ggpo_advance_frame
function GGPO_Peer.AdvanceFrame()
end


-- ggpo_add_local_input
function GGPO_Peer.AddLocalInput<I>(input: GameInput<I>)
end

-- ggpo_start_session  (you still need to call addPlayer)
function GGPO_Peer.StartSession<T>(config: GameConfig, callbacks: GGPOCallbacks<T>)
end

function GGPO_Peer.AddSpectator(endpoint: UDPEndpoint)
end

function GGPO_Peer.AddPlayerProxy(player: PlayerProxyInfo)
end







--return GGPO_Peer


-- GGPO_SERVER
--local GGPO_Server = {}
-- inhert GGPO_Peer
--GGPO_Server.mt = {}
--GGPO_Server.mt.__index = function (table, key)
--    return GGPO_Peer[key]
--end



-- GGPO_CLIENT
--local GGPO_Client = {}



