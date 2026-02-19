// src/i18nProvider.ts
import polyglotI18nProvider from "ra-i18n-polyglot";
import spanishMessages from "ra-language-spanish";
import englishMessages from "ra-language-english";

/**
 * Objetivo:
 * - Evitar que aparezcan keys crudas tipo "ra.message.invalid_form"
 * - Cubrir notificaciones (created/updated/...) y acciones frecuentes
 * - Cubrir algunas variantes raras que a veces aparecen como "RA.*"
 *
 * Nota:
 * - Se hace merge: EN -> ES -> overrides
 *   Así: ES pisa EN, y overrides pisa todo. EN queda como fallback.
 */

const overridesEs: any = {
  ra: {
    action: {
      // Acciones generales
      add_filter: "Agregar filtro",
      add: "Agregar",
      back: "Volver",
      bulk_actions: "Acciones",
      cancel: "Cancelar",
      clear_array_input: "Limpiar lista",
      clear_input_value: "Limpiar valor",
      clone: "Duplicar",
      confirm: "Confirmar",
      create: "Crear",
      delete: "Eliminar",
      edit: "Editar",
      export: "Exportar",
      list: "Listado",
      refresh: "Actualizar",
      remove_filter: "Quitar filtro",
      remove: "Quitar",
      save: "Guardar",
      search: "Buscar",
      select_all: "Seleccionar todo",
      show: "Ver",
      sort: "Ordenar",
      undo: "Deshacer",
      unselect: "Deseleccionar",

      // A veces aparece como key faltante en SelectInput/Autocomplete
      clear_input: "Limpiar",
    },

    navigation: {
      // navegación/paginación
      no_results: "Sin resultados",
      no_more_results: "No hay más resultados",
      page_rows_per_page: "Filas por página:",
      page_range_info: "%{offsetBegin}-%{offsetEnd} de %{total}",
      next: "Siguiente",
      prev: "Anterior",
      first: "Primera",
      last: "Última",
    },

    notification: {
      // Notificaciones estándar Create/Edit/Delete
      created: "Creado correctamente",
      updated: "Actualizado correctamente",
      deleted: "Eliminado correctamente",
      bad_item: "Elemento incorrecto",
      item_doesnt_exist: "El elemento no existe",
      http_error: "Error al comunicarse con el servidor",
      data_provider_error: "Error del proveedor de datos",
      canceled: "Operación cancelada",
      logged_out: "Sesión cerrada",
      not_authorized: "No autorizado",
      i18n_error: "Error de traducción",
    },

    message: {
      // Mensajes genéricos
      about: "Acerca de",
      are_you_sure: "¿Estás seguro?",
      bulk_delete_content:
        "¿Seguro que querés eliminar %{name}? |||| ¿Seguro que querés eliminar %{smart_count} elementos?",
      bulk_delete_title: "Eliminar %{name} |||| Eliminar %{smart_count} elementos",
      delete_content: "¿Seguro que querés eliminar este elemento?",
      delete_title: "Eliminar %{name} #%{id}",
      details: "Detalle",
      error: "Ocurrió un error",
      invalid_form: "El formulario tiene errores. Revisá los campos marcados.",
      loading: "Cargando…",
      no: "No",
      yes: "Sí",
      not_found: "No encontrado",
      empty: "Vacío",
      unauthorized: "No autorizado",
    },

    auth: {
      // Auth messages típicos
      sign_in: "Iniciar sesión",
      sign_in_error: "Error de autenticación",
      logout: "Cerrar sesión",
      username: "Usuario",
      password: "Contraseña",

      // ✅ FALTANTES que te aparecen en consola
      auth_check_error: "No autorizado",
      user_menu: "Perfil",
      authentication_error: "Error de autenticación",
      login: "Iniciar sesión",

      // ✅ Algunos que RA puede pedir según versión/tema
      forgot_password: "¿Olvidaste tu contraseña?",
      invalid_email: "Email inválido",
      required: "Requerido",
    },

    validation: {
      // Validaciones habituales
      required: "Requerido",
      minLength: "Debe tener al menos %{min} caracteres",
      maxLength: "Debe tener como máximo %{max} caracteres",
      minValue: "Debe ser mayor o igual a %{min}",
      maxValue: "Debe ser menor o igual a %{max}",
      number: "Debe ser un número",
      email: "Debe ser un email válido",
      oneOf: "Debe ser uno de: %{options}",
      regex: "Formato inválido",
    },

    input: {
      // Claves usadas por inputs (especialmente file/select)
      file: {
        upload_several: "Arrastrá archivos para subirlos o hacé clic para seleccionar",
        upload_single: "Arrastrá un archivo para subirlo o hacé clic para seleccionar",
      },
      image: {
        upload_several: "Arrastrá imágenes para subirlas o hacé clic para seleccionar",
        upload_single: "Arrastrá una imagen para subirla o hacé clic para seleccionar",
      },
      references: {
        all_missing: "No se pudieron encontrar referencias",
        many_missing: "Algunas referencias ya no están disponibles",
        single_missing: "La referencia asociada ya no está disponible",
      },

      password: {
        toggle_hidden: "Mostrar contraseña",
        toggle_visible: "Ocultar contraseña",
      },
    },

    sort: {
      sort_by: "Ordenar por %{field} %{order}",
      ASC: "ascendente",
      DESC: "descendente",
    },

    page: {
      create: "Crear %{name}",
      dashboard: "Inicio",
      edit: "%{name} #%{id}",
      error: "Ocurrió un error",
      list: "%{name}",
      loading: "Cargando…",
      not_found: "No encontrado",
      show: "%{name} #%{id}",
      empty: "Sin %{name} todavía.",
      invite: "¿Querés crear uno?",
    },
  },

  /**
   * Variantes “raras” (algunas integraciones o logs muestran keys en mayúscula)
   * Las cubrimos para que nunca se vea feo.
   */
  "RA.CREATED": "Creado correctamente",
  "RA.UPDATED": "Actualizado correctamente",
  "RA.DELETED": "Eliminado correctamente",
  "RA.MESSAGE.INVALID_FORM": "El formulario tiene errores. Revisá los campos marcados.",
  "RA.MESSAGE.INVALID_FORM_WARNING":
    "El formulario tiene errores. Revisá los campos marcados.",
  "RA.ACTION.CLEAR_INPUT_VALUE": "Limpiar valor",
  "RA.ACTION.EXPORT": "Exportar",
  "RA.ACTION.SAVE": "Guardar",
  "RA.ACTION.CANCEL": "Cancelar",
  "RA.NAVIGATION.NEXT": "Siguiente",
  "RA.NAVIGATION.PREV": "Anterior",
  "RA.NAVIGATION.PAGE_ROWS_PER_PAGE": "Filas por página:",
};

export const i18nProvider = polyglotI18nProvider(
  (locale) => {
    if (locale === "es") {
      // EN -> ES -> overrides (EN queda como fallback)
      return { ...englishMessages, ...spanishMessages, ...overridesEs };
    }
    // EN por default
    return englishMessages;
  },
  "es",
  [
    { locale: "es", name: "Español" },
    { locale: "en", name: "English" },
  ]
);
