package steward

import "encoding/base64"

func base64StdDecode(value string) ([]byte, error) { return base64.StdEncoding.DecodeString(value) }
