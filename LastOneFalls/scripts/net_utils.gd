extends RefCounted
## Pure, stateless helpers for the LAN code (no autoload needed, easy to unit-test).
##
## ROOT CAUSE of "valid IPv4 rejected": on Arabic / Persian Android keyboards the numeric field types
## Arabic-Indic (U+0660..0669) or Persian (U+06F0..06F9) digits and Arabic separators (U+066B, U+060C).
## String.is_valid_ip_address() only accepts ASCII, so "١٩٢.١٦٨.٤٣.١" was rejected although it is valid.
## Everything typed by the player is therefore normalised to ASCII first, then validated strictly.


## Replaces localized digits / separators by ASCII and strips invisible bidi marks and odd spaces.
static func normalize_text(raw: String) -> String:
	var out := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c >= 0x0660 and c <= 0x0669:          # Arabic-Indic digits
			out += char(c - 0x0660 + 48)
		elif c >= 0x06F0 and c <= 0x06F9:        # Persian / Urdu digits
			out += char(c - 0x06F0 + 48)
		elif c >= 0xFF10 and c <= 0xFF19:        # full-width digits
			out += char(c - 0xFF10 + 48)
		elif c == 0x066B or c == 0x060C or c == 0x06D4 or c == 0xFF0E or c == 0x3002 or c == 0x002C:
			out += "."                           # Arabic decimal sep., Arabic comma, full stops, ","
		elif c == 0x00A0 or c == 0x3000 or c == 0x2009 or c == 0x202F:
			out += " "
		elif (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069) or c == 0xFEFF or c == 0x061C:
			continue                             # zero-width / RTL / LTR marks added by IMEs and paste
		else:
			out += char(c)
	return out.strip_edges()


## Returns the canonical dotted-quad ("192.168.43.1") or "" when the text is not a usable IPv4 address.
static func parse_ipv4(raw: String) -> String:
	var s := normalize_text(raw)
	if s.is_empty() or s.length() > 15:
		return ""
	var parts := s.split(".", true)
	if parts.size() != 4:
		return ""
	var nums: Array = []
	for p in parts:
		if p.is_empty() or p.length() > 3:
			return ""
		for i in p.length():
			var c := p.unicode_at(i)
			if c < 48 or c > 57:
				return ""
		var v := int(p)
		if v > 255:
			return ""
		nums.append(v)
	# 0.x.x.x = unspecified, >=224 = multicast / reserved / broadcast: never a valid host to join.
	if int(nums[0]) == 0 or int(nums[0]) >= 224:
		return ""
	return "%d.%d.%d.%d" % nums


## Returns the port (1024..65535) or -1.
static func parse_port(raw: String) -> int:
	var s := normalize_text(raw)
	if s.is_empty() or s.length() > 5:
		return -1
	for i in s.length():
		var c := s.unicode_at(i)
		if c < 48 or c > 57:
			return -1
	var v := int(s)
	if v < 1024 or v > 65535:
		return -1
	return v


## Removes control characters and limits the length of text that comes from the network.
static func clean_net_text(raw: String, max_len: int) -> String:
	var out := ""
	for i in raw.length():
		var c := raw.unicode_at(i)
		if c < 32 or c == 127 or (c >= 0x200B and c <= 0x200F) or (c >= 0x202A and c <= 0x202E) or (c >= 0x2066 and c <= 0x2069):
			continue
		out += char(c)
	out = out.strip_edges()
	if out.length() > max_len:
		out = out.substr(0, max_len)
	return out


## Addresses a discovery query is sent to, for every local IPv4 (assumes /24, the default of Android hotspots
## and most home routers): the subnet broadcast, the usual gateway/hotspot address (.1, a plain unicast that
## still works on networks that drop broadcasts) and the global broadcast.
static func discovery_targets(local_ips: Array) -> Array:
	var out: Array = []
	for ip in local_ips:
		var s := str(ip)
		if s.contains(":") or s.begins_with("127.") or s.begins_with("169.254."):
			continue
		var p := s.split(".")
		if p.size() != 4:
			continue
		var prefix := "%s.%s.%s." % [p[0], p[1], p[2]]
		for t in [prefix + "255", prefix + "1"]:
			if t != s and not out.has(t):
				out.append(t)
	out.append("255.255.255.255")
	return out
