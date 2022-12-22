local M = {}

local Juggler = {}

function Juggler.update(self)
	for i = #self.tasks, 1, -1 do
		local t = self.tasks[i]
		local alive = true
		if t.type == "co" then
			local status = coroutine.status(t.fn)
			if status == "suspended" then
				local success, result = coroutine.resume(t.fn)
				if not success then
					alive = false
					print("Error exec co "..result)
				end
			elseif status == "dead" then
				alive = false
			end
		elseif t.type == "collection_proxy" then
			alive = not t.task.done
		end
		
		if not alive then
			print("complete task: "..t.type)
			table.remove(self.tasks, i)
		end
	end
end

function Juggler.on_message(self, message_id, message, sender)
	if message_id == hash("proxy_loaded") then
		for _, t in ipairs(self.tasks) do
			if t.type == "collection_proxy" and t.proxy == sender then
				print("Collection proxy loaded: "..t.name)
				t.task.done = true
				msg.post(t.proxy, "init")
				msg.post(t.proxy, "enable")
			end
		end
	end
end

function Juggler.co(self, fn)
	table.insert(self.tasks, {
		type = "co",
		fn = coroutine.create(fn)
	});
end

function Juggler.load_collection_proxy(self, name, proxy)
	local pending_count = 0;
	function check_pendings()
		if pending_count == 0 then
			print(name.." start loading")
			msg.post(proxy, "load")
		else
			print(name.." pending for "..pending_count)
		end
	end

	local manifest = resource.get_current_manifest()
	local missing = collectionproxy.missing_resources(proxy)
	for _, hash in ipairs(missing) do
		pending_count = pending_count + 1
		local url = "./updates/"..hash
		print("Request "..url)
		http.request(url, "GET", function(self, _, resp)
			print("Responce "..url.." "..resp.status)
			if resp.status == 200 or resp.status == 304 then
				resource.store_resource(manifest, resp.response, hash, function(self, _, status)
					if status then
						pending_count = pending_count - 1
						check_pendings()
					else
						print("Error when stored "..hash)
					end
				end)
			else
				print("Error load "..hash)
			end
		end)
	end
	
	local task = { done = false }
	
	table.insert(self.tasks, {
		type = "collection_proxy",
		name = name,
		proxy = proxy,
		task = task
	});

	check_pendings()
	
	while not task.done do
		coroutine.yield()
	end
end

function M.juggler()
	local j = {
		tasks = {},
	}
	setmetatable(j, { __index = Juggler })
	return j
end

return M