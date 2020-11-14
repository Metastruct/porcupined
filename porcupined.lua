#!/home/srcds/.nginx/luajit/bin/luajit

-- CONSTS

local addr = "porcupined.socket"

-- LIBS

local ffi = require'ffi'
local socket = require'socket'
require'socket.unix'
local vstruct = require'vstruct'

local porcupine = require'porcupine'

local C = ffi.load'/home/srcds/gserv/.steamcmd/linux64/steamclient.so'
local C = ffi.load'/home/srcds/gbins/sdk/redistributable_bin/linux64/libsteam_api.so'
local steamvoice = require'steem'
local os = require'os'
local unistd = require 'posix.unistd'
local io = require'io'
local syswait = require 'posix.sys.wait'

-- HELPERS
local function Now()
	return socket.gettime()
end
local function close_socket(sock)
	-- workaround for close causing non-blocking status to reset
	local fd = sock:getfd()
	local ret = unistd.close(fd)
	sock:setfd(-1)
	sock:close()
	return ret
end

-- initialization

local DEBUG=os.getenv("PORCUPINED_DEBUG")=='1'
local test_random = (os.getenv("TEST_RANDOM")=='1')
local function dbg()end
if DEBUG then
	dbg=print
end


io.stdin:close()
os.remove(addr)
local len_reader = vstruct.compile("u4")

-- Server socket
	local server = assert(socket.unix())
	--assert(server:bind("::1",20022))
	assert(server:bind(addr))
	assert(server:listen(5))
	--assert(server:setoption("reuseaddr",true))
	server:settimeout(0)
	
print"Porcupined v0.2 ready to accept connections"

local endpoint
local ischild
local childpids = {}
local spawned_children = 0
local now = Now()
local last_childrencount = 0

collectgarbage()
collectgarbage()
local FDSET={}

while true do
	local err
	FDSET[1]=server
	local R,T,E = socket.select(FDSET,nil,0.1)
	if next(R) then
		server:settimeout(0)
		endpoint,err = server:accept()
	else
		if E~='timeout' then
			print("ERR",E)
		end
		endpoint,err = nil,'timeout'
	end
	
	if endpoint then
		local childpid = unistd.fork()
		assert(childpid and childpid~=-1)
		
		ischild = childpid == 0
		if ischild then
			print("I AM A CHILD",spawned_children+1,"pid=",unistd.getpid())
			break
		else
			-- server does not need ref to it anymore
			print(ischild)
			close_socket(endpoint)
			spawned_children = spawned_children + 1
			childpids[childpid]=true
		end
	elseif err=='timeout' then
		-- retry
	else
		assert(endpoint,err)
	end
	
	local childrencount=0
	for pid,_ in next,childpids do
--		print("waiting",pid)
		local _pid, status, code = syswait.wait(pid, syswait.WNOHANG)
--		print("wait",pid, status, code)
		
		if status=="running" then
			childrencount = childrencount + 1
		elseif _pid==nil and code==10 then
			childpids[pid]=nil
			print("CHILD ",pid,"REAPED",_pid,status,code)
		end
		
	end
	if last_childrencount~=childrencount then
		print("Server has ",childrencount," children")
		last_childrencount = childrencount
	end
end

if not ischild then
	print("==========")
	print("========== SERVER PROCESS DED ============")
	print("==========")
	return
	os.exit(0)
end

assert(ischild)
close_socket(server)

-- TODO
--assert(endpoint:settimeout(0))

endpoint:send("state=1\n")
print""print""
steamvoice.init()
print""print""
endpoint:send("state=2\n")

--socket.sleep(999999)


dbg(
	"Porcupine version:",porcupine.version(),
	"sample_rate()=",porcupine.sample_rate(),
	"frame_length()=",porcupine.frame_length()
	)
	
local porc = assert(porcupine.new())

local porc_want_bytes = porcupine.frame_length() * 2

local carry = ffi.C.malloc(porc_want_bytes)
local empty_buff = ffi.C.malloc(porc_want_bytes)
ffi.fill(empty_buff,porc_want_bytes,0)

if test_random then
	ffi.fill(carry,porc_want_bytes,math.random(1,254))
end
local carry_bytes = 0

local function on_voice_pcm(buff_in,buff_in_len)
	dbg("-----------------------","len:",buff_in_len or "FLUSH BUFFER")
	if not buff_in then
		buff_in = empty_buff
		buff_in_len = porc_want_bytes-carry_bytes
		print("flushing",buff_in_len,"empty bytes")
	end
	local buff = porc._in_buf
	if test_random then
		ffi.fill(buff,porc_want_bytes,math.random(1,254))
	end
	
	local buff_ptr = porc._in_buf_ptr
	local buff_consumed=0

	for i=1,8192 do
		
		local want_bytes_from_buff = porc_want_bytes - carry_bytes
		assert(want_bytes_from_buff>=0,want_bytes_from_buff)
		local carry_offset = 0
		local buff_remaining = buff_in_len-buff_consumed
		
		if want_bytes_from_buff==0 or want_bytes_from_buff>buff_remaining then
			break
		end
		
		-- we have a carry
		if carry_bytes>0 then
			dbg("carrying",carry_bytes)
			ffi.copy(buff,carry,carry_bytes)
			carry_offset=carry_bytes
			carry_bytes=0
			if test_random then
				ffi.fill(carry,porc_want_bytes,math.random(1,254))
			end
		end
		
		dbg("consume ",want_bytes_from_buff,"consumed",buff_consumed)
		ffi.copy(ffi.cast("int8_t*",buff)+carry_offset,ffi.cast("int8_t*",buff_in)+buff_consumed,want_bytes_from_buff)
		buff_consumed = buff_consumed + want_bytes_from_buff
		
		--if DEBUG then
		--	local str = ffi.string(buff,porc_want_bytes)
		--	sample_out:write(str)
		--	
		--end
		
		local ret,err = porc:process(buff_ptr)
		if ret==nil then
			dbg("porcupine","ERROR",ret,err)
		elseif ret==false then
		else
			print("porcupine","GOTCHA!",ret)
			endpoint:send("detect="..tostring(ret)..'\n')
		end
	end
	if buff_consumed<buff_in_len and buff_in_len>0 then
		local remaining = buff_in_len-buff_consumed
		if remaining> 0 then
			if carry_bytes>0 then
				dbg("!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!!",carry_bytes)
			end
			ffi.copy(ffi.cast("int8_t*",carry)+carry_bytes,ffi.cast("int8_t*",buff_in)+buff_consumed,buff_in_len-buff_consumed)
			carry_bytes = carry_bytes + remaining
		end
	end
	dbg("carrying to next frame\t",carry_bytes)


end


local function on_voice_stream_data(buff,buff_len)
	if not buff then
		-- buffer flushing
		return on_voice_pcm()
	end
	local ret,len = steamvoice.decompress_voice(buff,buff_len)
	if ret==nil then
		dbg("steamvoice",len)
		return
	end
	if ret==false then
		dbg("steamvoice","Beginning of transmission?")
		return
	end
	
	if ret and len then
		
		--if DEBUG then
			--local data = ffi.string(ret,len)
			--sample_out2:write(data)
		--end
		
		on_voice_pcm(ret,len)
		return 
		
	end
	
	error"?"
	
end

local function receive_buffered(sock,want_bytes,state)
	if not state.len then
		state.len = 0
		state.buffer = {}
	end
	local rbytes = want_bytes-state.len
	local recv,err,partial = sock:receive(rbytes)
	if recv=="" then recv=nil end
	if partial=="" then partial=nil end
	
	if recv or err=='timeout' then
		if not recv and not partial then
			return nil,'timeout'
		end
		
		recv = recv or partial
		table.insert(state.buffer,recv)
		state.len = state.len + #recv
		
		if state.len>=want_bytes then
			assert(state.len<=want_bytes,"buffer overfull")
			local ret = table.concat(state.buffer,"")
			for i=#state.buffer,1,-1 do
				state.buffer[i]=nil
			end
			state.len=0
			return ret
		end
	end
	return recv,err
end

local buff_len = 8192
local buff = ffi.C.malloc(buff_len)
local buff_ptr = ffi.cast("void *",buff)
local finish_receiving
local rbufferobj={}
local function pump_data()
	
	if finish_receiving then
		endpoint:settimeout(0.3)
	end
	local lendata,err = receive_buffered(endpoint,4,rbufferobj)
	if finish_receiving then
		if not lendata and err=='timeout' then
			finish_receiving=false
			on_voice_stream_data()
		end
		endpoint:settimeout(-1)
	end
	if not lendata then
		if err=='timeout' then
			return
		else
			print("CHILD",endpoint,err)
			return true
		end
	end
	
	if #lendata~=4 then
		print("RECEIVE FAILURE?",#lendata)
		return true
	end
	
		
	local datalen = len_reader:read(lendata)[1]
	
		
	assert(buff_len>datalen,"datalen>buff: "..tostring(datalen))
	local data,err = endpoint:receive(datalen)
	
	if not data or #data ~= datalen then
		dbg("bork",data and #data or "EOF",err)
		return true
	end
	ffi.copy(buff,data,datalen)
	finish_receiving = true
	on_voice_stream_data(buff,datalen)

end

-- dying at some point is fine, everything will reinitialize
for i=1,9999999 do
	if pump_data() then dbg"PUMP DONE" break end
end

if test then

	local buff_len = 8192
	local buff = ffi.C.malloc(buff_len)
	local buff_ptr = ffi.cast("void *",buff)

	local sample = assert(io.open("voice_22.dat",'rb'))
	local len_reader = vstruct.compile("u4")

	local function pump_data()
		local lendata = sample:read(4)
		if not lendata or #lendata~=4 then
			return true
		end
		
		local datalen = len_reader:read(lendata)[1]
		
		assert(buff_len>datalen)
		local data = sample:read(datalen)
		
		if not data or #data ~= datalen then
			dbg("bork",data and #data or "EOF","EOF?")
			return true
		end
		
		ffi.copy(buff,data,datalen)
		on_voice_stream_data(buff,datalen)

	end

	for i=1,8192 do
		if pump_data() then dbg"PUMP DONE" break end
	end
	dbg"END LOOP"
	if DEBUG then
		--sample_out:flush()
		--sample_out:close()
		--sample_out2:flush()
		--sample_out2:close()
		--
		--sample_out = assert(io.open("voice_out.porc.raw",'rb'))
		--sample_out2 = assert(io.open("voice_out.steam.raw",'rb'))
		--local data1 = sample_out:read("*all")
		--local data2 = sample_out2:read("*all")
		--local len = math.min(#data1,#data2)-1
		--assert(data1:sub(1,len)==data2:sub(1,len),"different bytes")
		--sample_out:close()
		--sample_out2:close()
	end
	--socket.sleep(99999999)
end