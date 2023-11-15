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
local ngx_header = ngx.header
local req_http_version = ngx.req.http_version
local str_sub = string.sub
local ipairs = ipairs
local tonumber = tonumber
local type = type
local brotlienc = require("brotli.encoder")


local lrucache = core.lrucache.new({
    type = "plugin",
})


local schema = {
    type = "object",
    properties = {
        types = {
            anyOf = {
                {
                    type = "array",
                    minItems = 1,
                    items = {
                        type = "string",
                        minLength = 1,
                    },
                },
                {
                    enum = {"*"}
                }
            },
            default = {"text/html"}
        },
        min_length = {
            type = "integer",
            minimum = 1,
            default = 20,
        },
        comp_level = {
            type = "integer",
            minimum = 1,
            maximum = 11,
            default = 1,
        },
        lgwin = {
            type = "integer",
            minimum = 10,
            maximum = 24,
            default = 24,
        },
        http_version = {
            enum = {1.1, 1.0},
            default = 1.1,
        },
        vary = {
            type = "boolean",
        }
    },
}


local _M = {
    version = 0.1,
    priority = 996,
    name = "brotli",
    schema = schema,
}


function _M.check_schema(conf)
    return core.schema.check(schema, conf)
end


local function create_brotli_encoder(lgwin, comp_level)
    core.log.info("create new brotli encoder")
    options = {
        lgwin = lgwin,
        quality = comp_level,
    }
    return brotlienc.new(options)
end


local function brotli_compress(conf, ctx, body)
    local encoder, err = core.lrucache.plugin_ctx(lrucache, ctx, nil,
                                                  create_brotli_encoder, conf.comp_level, conf.lgwin)
    if not encoder then
        core.log.error("failed to create brotli encoder: ", err)
        return
    end
    compressed = encoder.compressStream(body)
    if encoder.isFinished() then
        return compressed
    end
end


function _M.header_filter(conf, ctx)
    local types = conf.types
    local content_type = ngx_header["Content-Type"]
    if not content_type then
        -- Like Nginx, don't compress if Content-Type is missing
        return
    end

    if type(types) == "table" then
        local matched = false
        local from = core.string.find(content_type, ";")
        if from then
            content_type = str_sub(content_type, 1, from - 1)
        end

        for _, ty in ipairs(types) do
            if content_type == ty then
                matched = true
                break
            end
        end

        if not matched then
            return
        end
    end

    local content_length = tonumber(ngx_header["Content-Length"])
    if content_length then
        local min_length = conf.min_length
        if content_length < min_length then
            return
        end
        -- Like Nginx, don't check min_length if Content-Length is missing
    end

    local http_version = req_http_version()
    if http_version < conf.http_version then
        return
    end

    if conf.vary then
        core.response.add_header("Vary", "Accept-Encoding")
    end

    core.response.clear_header_as_body_modified()
    ctx.brotli_matched = matched
end


function _M.body_filter(conf, ctx)
    if ctx.brotli_matched then
        local body = core.response.hold_body_chunk(ctx)
        if ngx.arg[2] == false and not body then
            return
        end

        local compressed = brotli_compress(conf, ctx, body)
        if not compressed then
            core.log.error("failed to compress response body")
            return
        end

        ngx.arg[1] = compressed
    end
end


return _M
