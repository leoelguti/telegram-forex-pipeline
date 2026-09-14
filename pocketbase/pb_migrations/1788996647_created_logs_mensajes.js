/// <reference path="../pb_data/types.d.ts" />
migrate((app) => {
  const collection = new Collection({
    "createRule": "",
    "deleteRule": "",
    "fields": [
      {
        "autogeneratePattern": "[a-z0-9]{15}",
        "help": "",
        "hidden": false,
        "id": "text3208210256",
        "max": 15,
        "min": 15,
        "name": "id",
        "pattern": "^[a-z0-9]+$",
        "presentable": false,
        "primaryKey": true,
        "required": true,
        "system": true,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "help": "",
        "hidden": false,
        "id": "text1759206190",
        "max": 0,
        "min": 0,
        "name": "canal_id",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "help": "",
        "hidden": false,
        "id": "text484712223",
        "max": 0,
        "min": 0,
        "name": "telegram_msg_id",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "autogeneratePattern": "",
        "help": "",
        "hidden": false,
        "id": "text1457621424",
        "max": 0,
        "min": 0,
        "name": "mensaje_crudo",
        "pattern": "",
        "presentable": false,
        "primaryKey": false,
        "required": false,
        "system": false,
        "type": "text"
      },
      {
        "help": "",
        "hidden": false,
        "id": "json2244480812",
        "maxSize": 0,
        "name": "json_extraido",
        "presentable": false,
        "required": false,
        "system": false,
        "type": "json"
      },
      {
        "help": "",
        "hidden": false,
        "id": "select643686883",
        "maxSelect": 1,
        "name": "estado",
        "presentable": false,
        "required": false,
        "system": false,
        "type": "select",
        "values": [
          "DESCARTADO",
          "ERROR_PARSER",
          "RECHAZO_RIESGO",
          "ENVIADO_MT5"
        ]
      }
    ],
    "id": "pbc_3892681537",
    "indexes": [],
    "listRule": "",
    "name": "logs_mensajes",
    "system": false,
    "type": "base",
    "updateRule": "",
    "viewRule": ""
  });

  return app.save(collection);
}, (app) => {
  const collection = app.findCollectionByNameOrId("pbc_3892681537");

  return app.delete(collection);
})
