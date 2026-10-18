// Supervisor: управление сессией, диагностика и проверка профиля.
package main

import (
	"encoding/json"
	"fmt"
	"io"
	"os"

	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/autostart"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/localprofile"
	"github.com/Hecatoncheir/amnezia-proxy-manager/engine/internal/session"
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
	if len(args) == 3 && args[0] == "--autostart" {
		enabled, err := autostart.Apply(args[1], args[2])
		if err != nil {
			return fmt.Errorf("не удалось изменить автозапуск")
		}
		return json.NewEncoder(output).Encode(map[string]any{"enabled": enabled})
	}
	if len(args) == 1 && args[0] == "--ipc" {
		return session.Serve(os.Stdin, output)
	}
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
		return fmt.Errorf("используйте --capabilities, --inspect-backend или --validate-config PATH --sha256 HASH или --ipc")
	}
	return json.NewEncoder(output).Encode(map[string]any{
		"protocolVersion": 1, "status": "ready", "canStart": true,
		"backend": "bropines/awg-wireproxy", "upstreamRevision": upstream.Revision,
		"backendDistribution": "separate", "backendCliContract": 2,
		"canValidateConfig": true, "canValidateXray": true, "canImportLocalAmnezia": localprofile.Supported,
		"backends": []string{"bropines/awg-wireproxy", "XTLS/Xray-core"}, "xrayVersion": upstream.XrayVersion,
	})
}
