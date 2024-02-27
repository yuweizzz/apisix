--
-- Licensed to the Apache Software Foundation (ASF) under one or more
-- contributor license agreements.  See the NOTICE file distributed with
-- this work for additional information regarding copyright ownership.
-- The ASF licenses this file to You under the Apache License, Version 2.0
-- (the "License"); you may not use this file except in compliance with
-- the License.  You may obtain a copy of the License at
--
--     http://www.apache.org/licenses/LICENSE-2.0
--
-- Unless required by applicable law or agreed to in writing, software
-- distributed under the License is distributed on an "AS IS" BASIS,
-- WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
-- See the License for the specific language governing permissions and
-- limitations under the License.
--
local core = require("apisix.core")
local resource = require("apisix.admin.resource")
local get_uri_args = ngx.req.get_uri_args
local schema_plugin = require("apisix.admin.plugins").check_schema

local function check_conf(id, conf, need_id, schema)
    local ok, err = core.schema.check(schema, conf)
    if not ok then
        return nil, {error_msg = "invalid configuration: " .. err}
    end

    local ok, err = schema_plugin(conf.plugins)
    if not ok then
        return nil, {error_msg = err}
    end

    return true
end


-- overwrite resource:get()
local function get(self, id)
    local arg = get_uri_args()
    local subsystem = arg["subsystem"] or "all"
    if subsystem ~= "http" and subsystem ~= "stream" and subsystem ~= "all" then
        return 400, {error_msg = "unsupported subsystem: "..subsystem}
    end

    local key = "/global_rules"
    if id then
        key = key .. "/" .. id
    end

    local res, err = core.etcd.get(key, not id)
    if not res then
        core.log.error("failed to get global rule [", key, "] from etcd: ", err)
        return 503, {error_msg = err}
    end

    if res.body.list then
        if subsystem == "all" then
            return res.status, res.body
        else
            for i = #res.body.list, 1, -1 do
                local matched = false
                if res.body.list[i].value.subsystem == subsystem then
                    matched = true
                end

                if not matched then
                    table.remove(res.body.list, i)
                end
            end
        end
    end

    return res.status, res.body
end


return resource.new({
    name = "global_rules",
    kind = "global rule",
    schema = core.schema.global_rule,
    checker = check_conf,
    get = get,
    unsupported_methods = {"post"}
})
