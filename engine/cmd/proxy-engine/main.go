// Диагностика и проверка профиля. Запуск туннеля ещё не реализован.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"
	"runtime"

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/localprofile"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/upstream"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/validation"
)

func main() {
	if err := run(os.Args[1:], os.Stdout); err != nil {
		fmt.Fprintln(os.Stderr, err)
		os.Exit(2)
	}
}

func run(args []string, output io.Writer) error {
	if len(args) == 4 && args[2] == "--sha256" && args[0] == "--probe-xray" {
		if err := validation.ProbeXray(args[1], args[3], os.Stdin); err != nil {
			return err
		}
		return json.NewEncoder(output).Encode(map[string]any{"httpsStatus": 200, "viaSocks": true, "stopped": true})
	}
	if len(args) == 4 && args[2] == "--sha256" && args[0] == "--validate-xray" {
		if err := validation.ValidateXray(args[1], args[3], os.Stdin); err != nil {
			return err
		}
		return json.NewEncoder(output).Encode(map[string]any{"valid": true})
	}
	if len(args) == 1 && args[0] == "--import-amnezia" {
		data, err := localprofile.ReadActive()
		if err != nil {
			return err
		}
		defer clear(data)
		_, err = output.Write(data)
		return err
	}
	if len(args) == 4 && args[0] == "--validate-config" && args[2] == "--sha256" {
		if err := validation.Validate(args[1], args[3], os.Stdin); err != nil {
			return err
		}
		return json.NewEncoder(output).Encode(map[string]any{"valid": true})
	}
	if len(args) == 4 && args[0] == "--inspect-backend" && args[2] == "--sha256" {
		if err := upstream.VerifyBinary(args[1], args[3]); err != nil {
			return err
		}
		return json.NewEncoder(output).Encode(map[string]any{
			"compatible": true, "upstreamRevision": upstream.Revision, "canStart": false,
		})
	}
	if len(args) != 1 || args[0] != "--capabilities" {
		return fmt.Errorf("используйте --capabilities, --inspect-backend или --validate-config PATH --sha256 HASH; запуск туннеля недоступен")
	}
	return json.NewEncoder(output).Encode(map[string]any{
		"protocolVersion": 1, "status": "scaffold", "canStart": false,
		"backend": "bropines/awg-wireproxy", "upstreamRevision": upstream.Revision,
		"backendDistribution": "separate", "backendCliContract": 2,
		"canValidateConfig": true, "canValidateXray": true, "canImportLocalAmnezia": runtime.GOOS == "windows",
		"backends": []string{"bropines/awg-wireproxy", "XTLS/Xray-core"}, "xrayVersion": upstream.XrayVersion,
	})
}
