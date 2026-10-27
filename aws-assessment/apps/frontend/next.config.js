/** @type {import('next').NextConfig} */
const nextConfig = {
  // "standalone" produces a minimal server bundle, ideal for the container image.
  output: process.env.BUILD_TARGET === "static" ? "export" : "standalone",
  reactStrictMode: true,
};

module.exports = nextConfig;
