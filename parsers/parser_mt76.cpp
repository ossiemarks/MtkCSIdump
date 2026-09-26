#include "parser_mt76.h"

#include "wifi_drv_api/mt76_api.h"

#include <vector>

std::vector<std::vector<double>> ParserMT76::processRawData(void *data, int antIdx)
{
    std::vector<csi_data *> *list = (std::vector<csi_data *>*)data;
    std::vector<std::vector<double>> tones_per_packet[ANTENNA_NUM];

    if (antIdx < 0 || antIdx >= ANTENNA_NUM)
        return {};

    for (size_t it = 0; it < list->size(); it++)
    {
        int num_subcarriers = CSI_BW20_DATA_COUNT; // Default value
        
        csi_data *csi = list->at(it);
        if (csi && csi->rx_idx < ANTENNA_NUM)
        {
            //fprintf(stderr, "\tprocessRawData() csi->data_num: %d\n", csi->data_num);
            
            // Determine number of subcarriers based on bandwidth
            switch (csi->ch_bw) {
                case 0: num_subcarriers = CSI_BW20_DATA_COUNT; break;   // 20MHz
                case 1: num_subcarriers = CSI_BW40_DATA_COUNT; break;   // 40MHz
                case 2: num_subcarriers = CSI_BW80_DATA_COUNT; break;   // 80MHz
                case 3: num_subcarriers = CSI_BW160_DATA_COUNT; break;  // 160MHz
                case 4: num_subcarriers = CSI_BW320_DATA_COUNT; break;  // 320MHz
                default: num_subcarriers = CSI_BW20_DATA_COUNT; break;  // Default to 20MHz
            }

            // Never read past what the driver actually delivered
            if (csi->data_num > 0 && csi->data_num < num_subcarriers)
                num_subcarriers = csi->data_num;

            if (csi->rx_idx == antIdx && num_subcarriers > 2)
            {
                // Skip first few subcarriers to avoid DC offset issues
                int start_idx = (num_subcarriers >= 64) ? 2 : 1;
                int end_idx = num_subcarriers - 1; // Also skip last subcarrier
                
                // Store raw I/Q pairs (interleaved: I, Q, I, Q, ...)
                std::vector<double> iq_data;
                
                for (int i = start_idx; i < end_idx; i++) {
                    iq_data.push_back(static_cast<double>(csi->data_i[i]));
                    iq_data.push_back(static_cast<double>(csi->data_q[i]));
                }
                
                tones_per_packet[antIdx].push_back(iq_data);
            }
            
            //fprintf(stderr, "\tprocessRawData() processed %d subcarriers\n", num_subcarriers);
        }
    }


    return tones_per_packet[antIdx];
}
