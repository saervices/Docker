// SPDX-License-Identifier: MIT
// Copyright (c) 2025 it.særvices

const http = require("http");

const request = http.get(
  {
    host: "127.0.0.1",
    port: 9000,
    path: "/socket.io/?EIO=4&transport=polling",
    timeout: 4000,
  },
  (response) => {
    let body = "";
    response.setEncoding("utf8");
    response.on("data", (chunk) => {
      body += chunk;
      if (body.length > 4096) request.destroy(new Error("oversized response"));
    });
    response.on("end", () => {
      process.exit(response.statusCode === 200 && body.startsWith("0{") ? 0 : 1);
    });
  },
);

request.on("timeout", () => request.destroy(new Error("timeout")));
request.on("error", () => process.exit(1));
