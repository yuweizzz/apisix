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

local _M = {}

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

local function new()
    return resource.new({
        name = "global_rules",
        kind = "global rule",
        schema = core.schema.global_rule,
        checker = check_conf,
        unsupported_methods = {"post"}
    })
end
_M.new = new


function _M.get(name)

    return 200, {info = name}
end


return _M
