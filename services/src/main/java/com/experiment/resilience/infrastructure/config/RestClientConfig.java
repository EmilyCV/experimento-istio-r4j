package com.experiment.resilience.infrastructure.config;

import org.apache.hc.client5.http.config.ConnectionConfig;
import org.apache.hc.client5.http.config.RequestConfig;
import org.apache.hc.client5.http.impl.classic.HttpClients;
import org.apache.hc.client5.http.impl.io.PoolingHttpClientConnectionManagerBuilder;
import org.apache.hc.core5.util.Timeout;
import org.springframework.beans.factory.annotation.Value;
import org.springframework.context.annotation.Bean;
import org.springframework.context.annotation.Configuration;
import org.springframework.http.client.HttpComponentsClientHttpRequestFactory;
import org.springframework.web.client.RestClient;

/**
 * Cliente HTTP usado pelo service-a para chamar o service-b.
 * É o MESMO em todas as variantes (mesmo pool de conexões); só o timeout
 * de leitura muda, pelas propriedades:
 *  - baseline e istio: 3000 ms (maior que o timeout total do Istio, 2 s);
 *  - r4j: 500 ms (é o timeout por tentativa do Resilience4j).
 */
@Configuration
public class RestClientConfig {

    @Bean
    public RestClient.Builder restClientBuilder(
            @Value("${app.http.connect-timeout-ms}") int connectTimeoutMs,
            @Value("${app.http.read-timeout-ms}") int readTimeoutMs) {

        // Timeouts de conexão e de leitura (tempo máximo esperando a resposta).
        var connectionConfig = ConnectionConfig.custom()
                .setConnectTimeout(Timeout.ofMilliseconds(connectTimeoutMs))
                .setSocketTimeout(Timeout.ofMilliseconds(readTimeoutMs))
                .build();

        // Pool de conexões reaproveitadas entre requisições.
        var connectionManager = PoolingHttpClientConnectionManagerBuilder.create()
                .setMaxConnTotal(100)
                .setMaxConnPerRoute(50)
                .setDefaultConnectionConfig(connectionConfig)
                .build();

        var requestConfig = RequestConfig.custom()
                .setConnectionRequestTimeout(Timeout.ofMilliseconds(1000))
                .setResponseTimeout(Timeout.ofMilliseconds(readTimeoutMs))
                .build();

        var httpClient = HttpClients.custom()
                .setConnectionManager(connectionManager)
                .setDefaultRequestConfig(requestConfig)
                // O retry fica só no Resilience4j ou no Istio, nunca no cliente HTTP.
                .disableAutomaticRetries()
                .build();

        return RestClient.builder()
                .requestFactory(new HttpComponentsClientHttpRequestFactory(httpClient));
    }
}
