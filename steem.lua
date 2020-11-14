local ffi=require'ffi'

-- TODO FIGURE OUT WHY NEEDED
local C = ffi.load'/home/srcds/gserv/.steamcmd/linux64/steamclient.so'
local C = ffi.load'/home/srcds/gbins/sdk/redistributable_bin/linux64/libsteam_api.so'

local steamworks


ffi.cdef[[

void *malloc(size_t size);
void free(void *ptr);


]]
local _M = {}
local voiceresults = {
	"k_EVoiceResultOK",
	"k_EVoiceResultNotInitialized",
	"k_EVoiceResultNotRecording",
	"k_EVoiceResultNoData",
	"k_EVoiceResultBufferTooSmall",
	"k_EVoiceResultDataCorrupted",
	"k_EVoiceResultRestricted",
	"k_EVoiceResultUnsupportedCodec",
	"k_EVoiceResultReceiverOutOfDate",
	"k_EVoiceResultReceiverDidNotAnswer",
}
function _M.voiceresult_to_string(vres)
	for k,v in next,voiceresults do
		if vres == ffi.C[v] then
			return v
		end
	end
end

local buff
local buffsz = 4000000
local nBytesWritten = ffi.new("uint32_t[1]", 0)
function _M.decompress_voice(datain,datain_len)
	
	datain_len = datain_len or #datain
	
	nBytesWritten[0]=0
	
	buff = buff or ffi.C.malloc(buffsz)
	local res = steamworks.user.DecompressVoice(datain, datain_len, buff, buffsz, nBytesWritten, 16000)
	
	if res ~= ffi.C.k_EVoiceResultOK then
		return nil,_M.voiceresult_to_string(res) or res
	end
	
	if nBytesWritten[0]==0 then
		return false,0
	end
	
	return buff, nBytesWritten[0]
	
end

function _M.init()
	steamworks = require'steamworks'
end

local vstruct = require'vstruct'
local len_reader = vstruct.compile("u4")

-- test 
if false then
	local steam = _M
	
	local sample = assert(io.open("voice_22.dat",'rb'))
	local sample_out = assert(io.open("voice_out.raw",'wb'))
	
	
	
	local buff_len = 8192
	local buff = ffi.C.malloc(buff_len)
	local buff_ptr = ffi.cast("void *",buff)
	local total=0
	local total_in=0
	for i=1,8192 do
		local lendata = sample:read(4)
		if not lendata or #lendata~=4 then
			print("EOF!")
			break
		end
		local datalen = len_reader:read(lendata)[1]
		total_in=total_in+datalen
		
		assert(buff_len>datalen)
		local data = sample:read(datalen)
		
		if not data or #data ~= datalen then
			print("bork",data and #data or "EOF","EOF?")
			break
		end
		
		ffi.copy(buff,data,datalen)
		local ret,ret2 = steam.decompress_voice(buff,datalen)
		if ret==nil then
			print(ret2)
		elseif ret==false then
			print("Beginning of transmission?")
		elseif ret and ret2 then
			io.stdout:write(".")
			io.stdout:flush()
			print("got",ret2,"bytes")
			local data = ffi.string(ret,ret2)
			assert(#data==ret2)
			total=total+#data
			sample_out:write(data)
		end
	end
	sample_out:flush()
	sample_out:close()
	sample:close()
	print("end!","decompressed",total,"bytes","from",total_in,"bytes")
end

return _M