import { Box, Typography } from "@mui/material";
import SearchOffIcon from "@mui/icons-material/SearchOff";

export const EmptyNoResults = () => {
  return (
    <Box
      sx={{
        p: 4,
        textAlign: "center",
        opacity: 0.8,
      }}
    >
      <SearchOffIcon sx={{ fontSize: 50, mb: 1 }} />

      <Typography variant="h6">
        No hay registros para los filtros seleccionados
      </Typography>

      <Typography variant="body2" color="text.secondary">
        Probá cambiar el rango de fechas u otros filtros.
      </Typography>
    </Box>
  );
};
